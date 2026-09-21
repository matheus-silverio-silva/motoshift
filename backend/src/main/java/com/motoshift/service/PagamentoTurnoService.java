package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.service.fiscal.CalculoTributario;
import com.motoshift.service.ledger.LedgerService;
import com.motoshift.service.ledger.Movimento;
import com.motoshift.service.ledger.Movimento.MotivoLiberacao;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * O dinheiro de um turno: reserva ao publicar, liquidacao ao finalizar,
 * liberacao ao cancelar ou expirar.
 *
 * <p><b>O que mudou, e por que.</b> Antes o pagamento dependia de as duas
 * partes apertarem um botao — o lojista dizia "paguei", o entregador dizia
 * "recebi", e so entao o saldo se movia. Isso tinha tres defeitos que nao eram
 * de implementacao, e sim da ideia:
 * <ul>
 *   <li>o credito do entregador nao tinha origem: ninguem era debitado, e o
 *       dinheiro simplesmente aparecia;</li>
 *   <li>nada garantia que o lojista tivesse o dinheiro — o turno era publicado
 *       sem lastro e a conta so chegava no fim;</li>
 *   <li>o entregador que trabalhou ficava refem de um clique alheio.</li>
 * </ul>
 *
 * <p><b>Como e agora.</b> Publicar RESERVA: sai do disponivel do lojista e vai
 * para o bloqueado dele. O dinheiro ja esta separado antes de qualquer
 * entregador aceitar. Finalizar TRANSFERE o que ja estava reservado, do
 * bloqueado do lojista para o disponivel do entregador, na mesma transacao que
 * encerra o turno. Nao ha confirmacao a dar, porque nao ha nada a confirmar: o
 * compromisso foi assumido na publicacao.
 *
 * <p><b>Quem pode finalizar continua sendo qualquer um dos dois participantes</b>
 * ({@link TurnoAcesso#exigirParticipante}) — e isso deixou de ser um risco.
 * Antes, quem finalizava disparava uma cobranca; hoje, finalizar so move
 * dinheiro que o lojista mesmo comprometeu ao publicar, e nem o valor nem o
 * destinatario dependem de quem clicou.
 *
 * <p>Todo o movimento de saldo sai daqui pelo {@link LedgerService}; este
 * servico decide O QUE mover e o ledger cuida de COMO.
 */
@Service
public class PagamentoTurnoService {

    private static final Logger log = LoggerFactory.getLogger(PagamentoTurnoService.class);

    private final TransacaoRepository transacaoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;
    private final LedgerService ledger;
    private final CalculoTributario tributos;

    public PagamentoTurnoService(TransacaoRepository transacaoRepo,
                                 TurnoInscricaoRepository inscricaoRepo,
                                 NotificacaoService notificacoes,
                                 LedgerService ledger,
                                 CalculoTributario tributos) {
        this.transacaoRepo = transacaoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
        this.ledger = ledger;
        this.tributos = tributos;
    }

    // -- Publicar ------------------------------------------------------------

    /**
     * Custo total de um turno: o valor por entregador vezes o numero de vagas.
     *
     * <p>{@code valorEstimado} sempre foi por entregador — o backend creditava
     * esse valor a cada um —, mas nada somava as vagas antes de publicar. Um
     * turno de 3 vagas a R$ 120 e um compromisso de R$ 360, e e esse numero que
     * precisa de lastro.
     */
    public static BigDecimal custoTotal(Turno turno) {
        BigDecimal valor = turno.getValorEstimado() == null
                ? BigDecimal.ZERO : turno.getValorEstimado();
        return valor.multiply(BigDecimal.valueOf(turno.getVagas()));
    }

    /**
     * Separa o dinheiro do turno na carteira do lojista.
     *
     * <p>Chamado na publicacao, dentro da mesma transacao que grava o turno: ou
     * o turno nasce com lastro, ou nao nasce. O 422 com quanto falta e montado
     * por quem chama ({@link TurnoService#criar}), que sabe o custo e o saldo;
     * aqui fica a garantia de ultima instancia do ledger.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public void reservar(Turno turno) {
        ledger.aplicar(Movimento.reserva(
                turno.getLojistId(), custoTotal(turno), turno.getId(), turno.getTitulo()));
    }

    // -- Finalizar -----------------------------------------------------------

    /**
     * Liquida o turno: paga cada entregador que trabalhou e devolve o resto.
     *
     * <p>Para cada inscricao finalizada, uma transferencia com os dois lados
     * (pagamento_enviado para o lojista, pagamento_recebido para o entregador,
     * mesmo operacaoId). O que sobrou da reserva — vagas que ninguem preencheu —
     * volta ao disponivel do lojista como liberacao_reserva.
     *
     * <p>A sobra e calculada pelo que foi REALMENTE reservado, lido do proprio
     * extrato, e nao recalculada a partir de vagas x valor. Se o turno foi
     * publicado com 3 vagas e a reserva gravada foi de R$ 360, e R$ 360 que tem
     * de sair do bloqueado, mesmo que alguem tenha mexido no turno depois.
     *
     * <p>Repetir esta chamada nao move dinheiro de novo: cada perna tem chave
     * deterministica e o ledger reencontra o que ja existe.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public void liquidar(Turno turno, List<TurnoInscricao> inscricoesFinalizadas) {
        BigDecimal reservado = garantirReserva(turno);
        BigDecimal valorPorEntregador = turno.getValorEstimado() == null
                ? BigDecimal.ZERO : turno.getValorEstimado();
        BigDecimal pago = BigDecimal.ZERO;

        for (TurnoInscricao ins : inscricoesFinalizadas) {
            if (ins.getMotoboyId() == null) continue;

            LedgerService.Transferencia t = ledger.transferir(
                    Movimento.pagamentoEnviado(turno.getLojistId(), ins.getMotoboyId(),
                            valorPorEntregador, turno.getId(), turno.getTitulo(),
                            chaveDaLiquidacao(ins, "debito")),
                    Movimento.pagamentoRecebido(ins.getMotoboyId(), turno.getLojistId(),
                            valorPorEntregador, turno.getId(), turno.getTitulo(),
                            chaveDaLiquidacao(ins, "credito")));

            BigDecimal retido = reterNaFonte(turno, ins, valorPorEntregador, t.operacaoId());

            ins.setPagamentoStatus(StatusPagamento.PAGO);
            inscricaoRepo.save(ins);
            pago = pago.add(valorPorEntregador);

            notificacoes.criar(ins.getMotoboyId(), "pagamento_confirmado",
                    "Pagamento recebido",
                    "O pagamento do turno \"" + turno.getTitulo()
                            + "\" foi creditado na sua carteira"
                            + (retido.signum() > 0
                                    ? ", com " + LedgerService.emReais(retido)
                                            + " retidos na fonte."
                                    : "."),
                    "carteira", turno.getId());
        }

        BigDecimal sobra = reservado.subtract(pago);
        if (sobra.signum() > 0) {
            ledger.aplicar(Movimento.liberacaoDeReserva(turno.getLojistId(), sobra, turno.getId(),
                    "Vagas não preenchidas: " + turno.getTitulo(), MotivoLiberacao.SOBRA));
        } else if (sobra.signum() < 0) {
            // Pagar mais do que foi reservado nao e um caso de negocio; se
            // acontecer, e defeito. O ledger ja barraria no bloqueado negativo —
            // este log existe para dizer QUAL turno, e nao so "saldo estranho".
            log.error("[pagamento] turno {} pagaria {} com reserva de {}",
                    turno.getId(), pago, reservado);
        }
    }

    /**
     * ISS e IRRF retidos do entregador, quando a retenção na fonte está ligada.
     *
     * <p>Dois débitos logo depois do crédito bruto, na mesma operação — ver
     * {@link Movimento#retencaoNaFonte}. A retenção não altera a
     * transferência: o lojista paga o valor cheio (que ele reservou), o
     * entregador recebe o valor cheio, e o tributo sai do entregador para o
     * fisco. Isso mantém o pagamento_recebido igual ao valor do serviço na
     * NFS-e com a retenção ligada ou desligada.
     *
     * <p>As chaves derivam da inscrição, como as da transferência: finalizar
     * de novo não retém de novo.
     *
     * @return quanto foi retido — zero com a retenção desligada
     */
    private BigDecimal reterNaFonte(Turno turno, TurnoInscricao ins, BigDecimal valor,
                                    UUID operacaoId) {
        if (!tributos.reterNaFonte() || valor.signum() <= 0) return BigDecimal.ZERO;

        CalculoTributario.Tributos t = tributos.calcular(valor);
        if (t.iss().signum() > 0) {
            ledger.aplicarNaOperacao(Movimento.retencaoNaFonte(ins.getMotoboyId(),
                    turno.getLojistId(), turno.getId(), TipoTransacao.RETENCAO_ISS, t.iss(),
                    turno.getTitulo(), chaveDaLiquidacao(ins, "retencao-iss")), operacaoId);
        }
        if (t.irrf().signum() > 0) {
            ledger.aplicarNaOperacao(Movimento.retencaoNaFonte(ins.getMotoboyId(),
                    turno.getLojistId(), turno.getId(), TipoTransacao.RETENCAO_IRRF, t.irrf(),
                    turno.getTitulo(), chaveDaLiquidacao(ins, "retencao-irrf")), operacaoId);
        }
        return t.total();
    }

    // -- Cancelar e expirar --------------------------------------------------

    /**
     * Devolve a reserva inteira ao disponivel do lojista.
     *
     * <p>Turno cancelado ou expirado nao gera pagamento nenhum, entao nada fica
     * bloqueado. Sem multa: a penalidade do cancelamento tardio e de score
     * (RF07) e continua onde estava — inventar uma multa financeira aqui seria
     * criar regra de negocio no meio de uma refatoracao.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public void liberarReserva(Turno turno, MotivoLiberacao motivo) {
        BigDecimal reservado = reservaDe(turno);
        if (reservado.signum() <= 0) {
            // Turno publicado antes do ledger: nao ha o que devolver. Nao e erro.
            return;
        }
        ledger.aplicar(Movimento.liberacaoDeReserva(turno.getLojistId(), reservado, turno.getId(),
                descricaoDaLiberacao(turno, motivo), motivo));
    }

    // -- Apoio ---------------------------------------------------------------

    /** Quanto este turno tem hoje separado na carteira do lojista. */
    private BigDecimal reservaDe(Turno turno) {
        return transacaoRepo.findByIdempotencyKey("reserva:turno:" + turno.getId())
                .map(Transacao::getValor)
                .orElse(BigDecimal.ZERO);
    }

    /**
     * A reserva do turno, criada agora se ele foi publicado antes do ledger.
     *
     * <p>Os turnos que ja estavam no banco quando esta versao subiu foram
     * publicados sem reserva nenhuma. Liquidar um deles tiraria do bloqueado um
     * dinheiro que nunca foi bloqueado — o ledger recusaria, e finalizar um
     * turno antigo viraria erro 500 sem explicacao.
     *
     * <p>Entao a reserva e feita na hora, a partir do disponivel do lojista. Se
     * ele nao tiver o valor, o 422 do ledger e a resposta certa e honesta: o
     * turno nunca teve lastro, e isso aparece agora em vez de virar credito sem
     * origem, que era exatamente o defeito antigo.
     */
    private BigDecimal garantirReserva(Turno turno) {
        BigDecimal reservado = reservaDe(turno);
        if (reservado.signum() > 0) return reservado;

        BigDecimal custo = custoTotal(turno);
        if (custo.signum() <= 0) return BigDecimal.ZERO;

        log.warn("[pagamento] turno {} foi publicado sem reserva (anterior ao ledger); "
                + "reservando {} agora para poder liquidar", turno.getId(), custo);
        reservar(turno);
        return custo;
    }

    private static String descricaoDaLiberacao(Turno turno, MotivoLiberacao motivo) {
        return switch (motivo) {
            case CANCELAMENTO -> "Turno cancelado: " + turno.getTitulo();
            case EXPIRACAO -> "Turno expirou sem entregador: " + turno.getTitulo();
            case SOBRA -> "Vagas não preenchidas: " + turno.getTitulo();
        };
    }

    /**
     * Chave de idempotencia de um lado da liquidacao.
     *
     * <p>Pela INSCRICAO e nao pelo par turno+entregador: a inscricao e a
     * identidade de "esta pessoa neste turno", e e ela que carrega o status de
     * pagamento. Os dois lados precisam de chaves diferentes porque sao dois
     * lancamentos e a coluna e unica; o que os une e o operacaoId.
     */
    static String chaveDaLiquidacao(TurnoInscricao ins, String lado) {
        return "liquidacao:inscricao:" + ins.getId() + ":" + lado;
    }

    /**
     * Inscricoes ativas de um turno, promovidas a FINALIZADO.
     *
     * <p>Fica aqui, e nao no {@link TurnoService}, porque a lista que muda de
     * status e exatamente a lista que vai ser paga — separar as duas coisas
     * abriria espaco para elas discordarem.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public List<TurnoInscricao> finalizarInscricoes(Turno turno) {
        List<TurnoInscricao> ativas =
                inscricaoRepo.findByTurnoIdAndStatus(turno.getId(), StatusInscricao.ACEITO);
        for (TurnoInscricao ins : ativas) {
            ins.setStatus(StatusInscricao.FINALIZADO);
            ins.setPagamentoStatus(StatusPagamento.PENDENTE);
            inscricaoRepo.save(ins);
        }
        return ativas;
    }

    /**
     * Turno de antes do sistema de vagas: ha entregador no turno e nenhuma
     * inscricao para ele.
     *
     * <p>A V5 fez o backfill e este caso deveria estar vazio. Se aparecer, a
     * inscricao e criada na hora — porque a alternativa e deixar alguem que
     * trabalhou sem receber, e porque toda a liquidacao e chaveada pela
     * inscricao. O WARN registra a linha que o backfill nao alcancou.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public TurnoInscricao inscricaoDeCompatibilidade(Turno turno) {
        if (turno.getMotoboyId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Turno sem motoboy atribuído.");
        }
        return inscricaoRepo.findByTurnoIdAndMotoboyId(turno.getId(), turno.getMotoboyId())
                .orElseGet(() -> {
                    log.warn("[pagamento] turno {} sem inscricao para o motoboy {}; "
                            + "a V5 nao cobriu esta linha e a inscricao esta sendo criada agora",
                            turno.getId(), turno.getMotoboyId());
                    TurnoInscricao ins = new TurnoInscricao();
                    ins.setTurnoId(turno.getId());
                    ins.setMotoboyId(turno.getMotoboyId());
                    ins.setStatus(StatusInscricao.FINALIZADO);
                    ins.setPagamentoStatus(StatusPagamento.PENDENTE);
                    return inscricaoRepo.save(ins);
                });
    }
}
