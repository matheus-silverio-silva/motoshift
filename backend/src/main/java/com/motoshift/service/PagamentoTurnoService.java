package com.motoshift.service;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
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
 * Continua havendo dois caminhos para a mesma regra, o de {@link TurnoInscricao}
 * e o "fallback legado" no proprio Turno, para os turnos aceitos antes do
 * sistema de vagas. A analise aponta isso como divida a pagar com um backfill;
 * enquanto o backfill nao acontece, os dois convivem aqui, lado a lado e
 * visiveis, em vez de espalhados.
 */
@Service
public class PagamentoTurnoService {

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
        TurnoInscricao ins = alvo == null ? null
                : inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, alvo).orElse(null);

        if (ins != null) {
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

        // Fallback legado (turno sem inscrições).
        if (turno.getLojistaConfirmouEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já confirmou o pagamento. Aguardando confirmação do motoboy.");
        }
        turno.setLojistaConfirmouEm(LocalDateTime.now());
        tentarEfetivarPagamento(turno);
        return mapper.toResponse(turnoRepo.save(turno));
    }

    // Motoboy declara que recebeu o pagamento.
    @Transactional
    public TurnoResponse confirmarRecebimentoMotoboy(Long turnoId, Long motoboyId) {
        Turno turno = carregarParaConfirmacao(turnoId);

        TurnoInscricao ins =
                inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, motoboyId).orElse(null);

        if (ins != null) {
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

        // Fallback legado (turno sem inscrições).
        if (turno.getMotoboyId() == null || !turno.getMotoboyId().equals(motoboyId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Apenas o motoboy do turno pode confirmar o recebimento.");
        }
        if (turno.getMotoboyConfirmouEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já confirmou o recebimento. Aguardando confirmação do lojista.");
        }
        turno.setMotoboyConfirmouEm(LocalDateTime.now());
        tentarEfetivarPagamento(turno);
        return mapper.toResponse(turnoRepo.save(turno));
    }

    /**
     * Transacao pendente do entregador naquele turno.
     *
     * Publico porque quem finaliza o turno e o {@link TurnoService}, e a
     * finalizacao e o momento em que a divida passa a existir.
     */
    public void criarTransacaoPendente(Turno turno, Long motoboyId) {
        if (motoboyId == null) return;
        Transacao tx = new Transacao();
        tx.setUsuarioId(motoboyId);
        tx.setContraparteId(turno.getLojistId());
        tx.setTurnoId(turno.getId());
        tx.setTipo("turno");
        tx.setValor(turno.getValorEstimado());
        tx.setDescricao("Turno finalizado: " + turno.getTitulo());
        // Transacao.status e outro dominio (pendente|processado|concluido) e
        // segue como String — nao confundir com StatusPagamento.
        tx.setStatus("pendente");
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
        marcarTransacaoProcessada(ins.getMotoboyId(), turno.getId());

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

    // Legado: efetiva pagamento no nível do turno (motoboy único, sem inscrições).
    private void tentarEfetivarPagamento(Turno turno) {
        if (turno.getLojistaConfirmouEm() == null
                || turno.getMotoboyConfirmouEm() == null) {
            return; // ainda aguardando a outra parte
        }
        turno.setPagamentoStatus(StatusPagamento.PAGO);
        creditarCarteira(turno.getMotoboyId(), turno.getValorEstimado());
        marcarTransacaoProcessada(turno.getMotoboyId(), turno.getId());
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

    // Marca a transação pendente daquele motoboy/turno como processada.
    private void marcarTransacaoProcessada(Long motoboyId, Long turnoId) {
        if (motoboyId == null) return;
        transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(motoboyId)
                .stream()
                .filter(t -> turnoId.equals(t.getTurnoId()) && "pendente".equals(t.getStatus()))
                .findFirst()
                .ifPresent(tx -> {
                    tx.setStatus("processado");
                    transacaoRepo.save(tx);
                });
    }
}
