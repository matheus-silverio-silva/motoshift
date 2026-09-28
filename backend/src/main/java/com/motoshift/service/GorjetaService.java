package com.motoshift.service;

import com.motoshift.dto.GorjetaResponse;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.ledger.LedgerService;
import com.motoshift.service.ledger.Movimento;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

/**
 * Gorjeta: o lojista dá ao entregador um valor além do turno, depois de
 * avaliá-lo.
 *
 * <p><b>Regras.</b>
 * <ul>
 *   <li>só o lojista do turno;</li>
 *   <li>só com o turno finalizado, e só a quem trabalhou nele (inscrição
 *       finalizada);</li>
 *   <li>uma por entregador por turno;</li>
 *   <li>de R$ 1,00 até {@code motoshift.gorjeta.maximo} (padrão R$ 50,00);</li>
 *   <li>só com saldo disponível — o bloqueado é das reservas.</li>
 * </ul>
 *
 * <p><b>Idempotente.</b> A chave é determinística —
 * {@code gorjeta:turno:{t}:entregador:{e}:debito|credito} —, no padrão do
 * pagamento de turno: repetir a mesma requisição (a rede caiu, o botão foi
 * tocado duas vezes) devolve a gorjeta que já existe e não cobra de novo.
 * Pedir OUTRO valor para o mesmo entregador no mesmo turno não é repetição, é
 * uma segunda gorjeta — e essa é recusada.
 *
 * <p><b>O dinheiro</b> passa pelo {@link LedgerService} como qualquer
 * transferência: débito no disponível do lojista ({@code bonus_enviado}),
 * crédito no disponível do entregador ({@code bonus}), mesma operação, os dois
 * ligados ao turno. Gera comprovante, não NFS-e — ver FISCAL.md.
 */
@Service
public class GorjetaService {

    private static final BigDecimal MINIMO = new BigDecimal("1.00");

    private final TurnoAcesso acesso;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final TransacaoRepository transacaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final CarteiraService carteiras;
    private final LedgerService ledger;
    private final NotificacaoService notificacoes;
    private final BigDecimal maximo;

    public GorjetaService(TurnoAcesso acesso,
                          TurnoInscricaoRepository inscricaoRepo,
                          TransacaoRepository transacaoRepo,
                          UsuarioRepository usuarioRepo,
                          CarteiraService carteiras,
                          LedgerService ledger,
                          NotificacaoService notificacoes,
                          @Value("${motoshift.gorjeta.maximo:50.00}") BigDecimal maximo) {
        this.acesso = acesso;
        this.inscricaoRepo = inscricaoRepo;
        this.transacaoRepo = transacaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.carteiras = carteiras;
        this.ledger = ledger;
        this.notificacoes = notificacoes;
        this.maximo = maximo;
    }

    @Transactional
    public GorjetaResponse dar(Long turnoId, Long lojistaId, Long entregadorId, BigDecimal valorPedido) {
        Turno turno = acesso.carregar(turnoId);
        if (!turno.getLojistId().equals(lojistaId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Só o lojista do turno dá gorjeta a quem trabalhou nele.");
        }
        if (turno.getStatus() != StatusTurno.FINALIZADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A gorjeta vem depois do turno finalizado.");
        }
        boolean trabalhou = entregadorId != null && inscricaoRepo
                .findByTurnoIdAndMotoboyId(turnoId, entregadorId)
                .filter(i -> i.getStatus() == StatusInscricao.FINALIZADO)
                .isPresent();
        if (!trabalhou) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Esse entregador não trabalhou neste turno.");
        }
        BigDecimal valor = validarValor(valorPedido);

        String chaveDebito = chave(turnoId, entregadorId, "debito");
        Transacao anterior = transacaoRepo.findByIdempotencyKey(chaveDebito).orElse(null);
        if (anterior != null) {
            if (anterior.getValor().compareTo(valor) == 0) {
                // A mesma gorjeta pedida de novo: nada se move.
                return GorjetaResponse.de(turnoId, entregadorId, anterior);
            }
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já deu uma gorjeta de " + LedgerService.emReais(anterior.getValor())
                            + " a este entregador neste turno.");
        }

        BigDecimal disponivel = carteiras.obterOuCriar(lojistaId).getSaldoDisponivel();
        if (disponivel.compareTo(valor) < 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Saldo insuficiente para a gorjeta de " + LedgerService.emReais(valor)
                            + ": você tem " + LedgerService.emReais(disponivel)
                            + " disponível. O saldo bloqueado é das reservas dos turnos.");
        }

        String nomeDaLoja = usuarioRepo.findById(lojistaId)
                .map(u -> u.getNomeFantasia() != null && !u.getNomeFantasia().isBlank()
                        ? u.getNomeFantasia() : u.getNome())
                .orElse("a loja");
        String nomeDoEntregador = usuarioRepo.findById(entregadorId)
                .map(Usuario::getNome).orElse("o entregador");

        Movimento.Par gorjeta = Movimento.gorjeta(lojistaId, entregadorId, valor, turnoId,
                nomeDoEntregador, nomeDaLoja, chave(turnoId, entregadorId, ""));
        LedgerService.Transferencia feita = ledger.transferir(gorjeta.debito(), gorjeta.credito());

        notificacoes.criar(entregadorId, "gorjeta_recebida",
                "Você recebeu uma gorjeta",
                "Você recebeu uma gorjeta de " + reaisCurto(valor) + " da " + nomeDaLoja
                        + " pelo turno \"" + turno.getTitulo() + "\".",
                "carteira", null);

        return GorjetaResponse.de(turnoId, entregadorId, feita.debito());
    }

    /** As gorjetas já dadas neste turno — para a tela saber a quem já deu. */
    public List<GorjetaResponse> doTurno(Long turnoId, Long usuarioId) {
        Turno turno = acesso.carregar(turnoId);
        acesso.exigirParticipante(turno, usuarioId);
        boolean ehLojista = usuarioId.equals(turno.getLojistId());
        return transacaoRepo.findByTurnoId(turnoId).stream()
                .filter(t -> t.getTipo() == TipoTransacao.BONUS_ENVIADO
                        && t.getStatus() == StatusTransacao.CONCLUIDO)
                // O entregador vê só a dele; o lojista, todas as do turno.
                .filter(t -> ehLojista || usuarioId.equals(t.getContraparteId()))
                .map(t -> GorjetaResponse.de(turnoId, t.getContraparteId(), t))
                .toList();
    }

    private BigDecimal validarValor(BigDecimal valor) {
        if (valor == null || valor.compareTo(MINIMO) < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A gorjeta é de pelo menos " + LedgerService.emReais(MINIMO) + ".");
        }
        if (valor.scale() > 2 && valor.stripTrailingZeros().scale() > 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Valor com mais de dois centavos de precisão.");
        }
        if (valor.compareTo(maximo) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A gorjeta vai até " + LedgerService.emReais(maximo) + ".");
        }
        return valor.setScale(2, RoundingMode.UNNECESSARY);
    }

    static String chave(Long turnoId, Long entregadorId, String lado) {
        String base = "gorjeta:turno:" + turnoId + ":entregador:" + entregadorId;
        return lado.isEmpty() ? base : base + ":" + lado;
    }

    /** "R$ 10" quando é inteiro, "R$ 7,50" quando não — como na notificação do prompt. */
    static String reaisCurto(BigDecimal v) {
        return v.stripTrailingZeros().scale() <= 0
                ? "R$ " + v.setScale(0, RoundingMode.UNNECESSARY).toPlainString()
                : LedgerService.emReais(v);
    }
}
