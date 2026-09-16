package com.motoshift.service;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

/**
 * O caminho do dinheiro: confirmacao das duas partes, liquidacao e credito.
 *
 * Estava misturado com criacao, aceite, listagem e filtro geografico em um
 * TurnoService de 604 linhas. Separar aqui nao e organizacao pela organizacao:
 * e o unico codigo do projeto que mexe em saldo, e quem for revisar essa regra
 * — ou defender em banca por que ela e segura — precisa conseguir ler o arquivo
 * inteiro de uma vez.
 *
 * Ha um caminho so: {@link TurnoInscricao}. Ate a V5 convivia aqui um "fallback
 * legado" que gravava a dupla confirmacao no proprio Turno, para os turnos
 * aceitos antes do sistema de vagas — toda regra de dinheiro escrita duas
 * vezes. A V5 fez o backfill (uma inscricao para cada turno com entregador) e
 * este servico passou a exigir a inscricao: sem ela e erro, nao rota alternativa.
 * A V6 removeu do Turno as colunas de confirmacao que o fallback usava.
 */
@Service
public class PagamentoTurnoService {

    private static final Logger log = LoggerFactory.getLogger(PagamentoTurnoService.class);

    private final TurnoRepository turnoRepo;
    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;
    private final TurnoMapper mapper;

    public PagamentoTurnoService(TurnoRepository turnoRepo,
                                 CarteiraRepository carteiraRepo,
                                 TransacaoRepository transacaoRepo,
                                 TurnoInscricaoRepository inscricaoRepo,
                                 NotificacaoService notificacoes,
                                 TurnoMapper mapper) {
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
        this.mapper = mapper;
    }

    // Lojista declara que enviou o pagamento a um entregador específico.
    // Pagamento só é efetivado quando AMBAS as partes confirmarem (anti-fraude).
    // motoboyId identifica qual entregador está sendo pago (multi-vaga). Se null,
    // usa o motoboy principal do turno (compatibilidade).
    @Transactional
    public TurnoResponse confirmarPagamentoLojista(Long turnoId, Long lojistaId, Long motoboyId) {
        Turno turno = carregarParaConfirmacao(turnoId);

        if (!turno.getLojistId().equals(lojistaId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Apenas o lojista do turno pode confirmar o pagamento.");
        }

        Long alvo = motoboyId != null ? motoboyId : turno.getMotoboyId();
        TurnoInscricao ins = exigirInscricao(turnoId, alvo);

        if (ins.getLojistaConfirmouEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já confirmou o pagamento deste entregador. Aguardando a confirmação dele.");
        }
        ins.setLojistaConfirmouEm(LocalDateTime.now());
        inscricaoRepo.save(ins);
        liquidarInscricao(turno, ins);
        atualizarPagamentoTurno(turno);
        return mapper.toResponse(turnoRepo.save(turno));
    }

    // Motoboy declara que recebeu o pagamento.
    @Transactional
    public TurnoResponse confirmarRecebimentoMotoboy(Long turnoId, Long motoboyId) {
        Turno turno = carregarParaConfirmacao(turnoId);

        // Quem nao participa do turno leva 403 antes de qualquer coisa — nao e
        // inconsistencia de dados, e gente pedindo o que nao e dela.
        if (turno.getMotoboyId() == null || !turno.getMotoboyId().equals(motoboyId)) {
            if (inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, motoboyId).isEmpty()) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                        "Apenas o motoboy do turno pode confirmar o recebimento.");
            }
        }

        TurnoInscricao ins = exigirInscricao(turnoId, motoboyId);

        if (ins.getMotoboyConfirmouEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já confirmou o recebimento. Aguardando confirmação do lojista.");
        }
        ins.setMotoboyConfirmouEm(LocalDateTime.now());
        inscricaoRepo.save(ins);
        liquidarInscricao(turno, ins);
        atualizarPagamentoTurno(turno);
        return mapper.toResponse(turnoRepo.save(turno));
    }

    /**
     * Chave de idempotencia do pagamento de um entregador num turno.
     *
     * Deterministica de proposito: e a mesma divida sempre que o par turno +
     * entregador se repete, entao uma segunda finalizacao nao cria uma segunda
     * divida, e a liquidacao encontra o lancamento pela chave em vez de varrer
     * o extrato. A V10 usou este mesmo formato no backfill das linhas antigas.
     */
    public static String chaveDoPagamento(Long turnoId, Long motoboyId) {
        return "pagamento_turno:" + turnoId + ":" + motoboyId;
    }

    /**
     * Transacao pendente do entregador naquele turno.
     *
     * Publico porque quem finaliza o turno e o {@link TurnoService}, e a
     * finalizacao e o momento em que a divida passa a existir.
     */
    public void criarTransacaoPendente(Turno turno, Long motoboyId) {
        if (motoboyId == null) return;
        String chave = chaveDoPagamento(turno.getId(), motoboyId);
        if (transacaoRepo.existsByIdempotencyKey(chave)) return;

        Transacao tx = new Transacao();
        tx.setUsuarioId(motoboyId);
        tx.setContraparteId(turno.getLojistId());
        tx.setTurnoId(turno.getId());
        tx.setTipo(TipoTransacao.PAGAMENTO_RECEBIDO);
        tx.setValor(turno.getValorEstimado());
        tx.setDescricao("Turno finalizado: " + turno.getTitulo());
        tx.setStatus(StatusTransacao.PENDENTE);
        tx.setIdempotencyKey(chave);
        transacaoRepo.save(tx);
    }

    /** Efetiva o pagamento de UMA inscrição quando ambas as partes confirmaram. */
    private void liquidarInscricao(Turno turno, TurnoInscricao ins) {
        if (ins.getLojistaConfirmouEm() == null || ins.getMotoboyConfirmouEm() == null) {
            return; // aguardando a outra parte
        }
        if (ins.getPagamentoStatus() == StatusPagamento.PAGO) return;

        ins.setPagamentoStatus(StatusPagamento.PAGO);
        inscricaoRepo.save(ins);
        creditarCarteira(ins.getMotoboyId(), turno.getValorEstimado());
        concluirTransacao(turno, ins.getMotoboyId());

        notificacoes.criar(ins.getMotoboyId(), "pagamento_confirmado",
                "Pagamento confirmado",
                "O pagamento do turno \"" + turno.getTitulo() + "\" foi creditado na sua carteira.",
                "carteira", turno.getId());
    }

    /** Turno vira PAGO quando todas as inscrições finalizadas foram pagas. */
    private void atualizarPagamentoTurno(Turno turno) {
        List<TurnoInscricao> participantes = inscricaoRepo.findByTurnoId(turno.getId())
                .stream()
                .filter(i -> i.getPagamentoStatus() != null)
                .collect(Collectors.toList());
        if (!participantes.isEmpty()
                && participantes.stream().allMatch(i -> i.getPagamentoStatus() == StatusPagamento.PAGO)) {
            turno.setPagamentoStatus(StatusPagamento.PAGO);
        }
    }

    private Turno carregarParaConfirmacao(Long turnoId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));
        if (turno.getStatus() != StatusTurno.FINALIZADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Só é possível confirmar pagamento de turnos finalizados.");
        }
        if (turno.getPagamentoStatus() == StatusPagamento.PAGO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já foi pago.");
        }
        return turno;
    }

    /**
     * A inscricao do entregador naquele turno, que depois da V5 sempre existe.
     *
     * Nao ha caminho alternativo: se cair aqui sem inscricao, o backfill nao
     * cobriu esta linha, e seguir adiante significaria creditar dinheiro por um
     * caminho que ninguem mais mantem. Melhor 500 alto e com log do que um
     * fluxo paralelo silencioso — que era exatamente o problema anterior.
     */
    private TurnoInscricao exigirInscricao(Long turnoId, Long motoboyId) {
        TurnoInscricao ins = motoboyId == null ? null
                : inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, motoboyId).orElse(null);

        if (ins == null) {
            log.error("[pagamento] turno {} sem inscricao para o motoboy {}. "
                    + "A V5 (backfill) nao cobriu esta linha; o pagamento nao pode "
                    + "ser liquidado sem inscricao.", turnoId, motoboyId);
            throw new IllegalStateException(
                    "Turno " + turnoId + " sem inscricao para o motoboy " + motoboyId);
        }
        return ins;
    }

    // Credita saldo na carteira do motoboy.
    private void creditarCarteira(Long motoboyId, BigDecimal valor) {
        if (motoboyId == null || valor == null) return;
        Carteira carteira = carteiraRepo.findByUsuarioId(motoboyId)
                .orElseGet(() -> {
                    Carteira c = new Carteira();
                    c.setUsuarioId(motoboyId);
                    return c;
                });
        // ganhosMensais saiu da carteira: era um contador que so crescia e
        // nunca zerava. O ganho do mes agora vem de CarteiraService.ganhosDoMes,
        // somado das transacoes.
        carteira.setSaldoDisponivel(carteira.getSaldoDisponivel().add(valor));
        carteiraRepo.save(carteira);
    }

    /**
     * Conclui a divida daquele entregador naquele turno.
     *
     * Antes carregava o extrato inteiro do entregador e procurava a pendente
     * comparando strings. Agora vai direto pela chave. Se a pendente nao
     * existir — linha antiga que o backfill da V10 nao conseguiu chavear —, o
     * lancamento e criado ja concluido: o saldo acabou de ser creditado, e todo
     * credito precisa aparecer no extrato.
     */
    private void concluirTransacao(Turno turno, Long motoboyId) {
        if (motoboyId == null) return;
        Transacao tx = transacaoRepo.findByIdempotencyKey(chaveDoPagamento(turno.getId(), motoboyId))
                .orElse(null);

        if (tx == null) {
            log.warn("[pagamento] turno {} sem lancamento pendente para o motoboy {}; "
                    + "registrando o credito ja concluido", turno.getId(), motoboyId);
            criarTransacaoPendente(turno, motoboyId);
            tx = transacaoRepo.findByIdempotencyKey(chaveDoPagamento(turno.getId(), motoboyId))
                    .orElseThrow();
        }
        if (tx.getStatus() == StatusTransacao.PENDENTE) {
            tx.setStatus(StatusTransacao.CONCLUIDO);
            transacaoRepo.save(tx);
        }
    }
}
