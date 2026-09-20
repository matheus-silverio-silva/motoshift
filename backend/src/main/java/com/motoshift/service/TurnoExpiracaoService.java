package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.ContagemPorTurno;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Vencimento automático de turnos (SCRUM-19).
 *
 * Regras deliberadas:
 *  - Turno ABERTO que ninguém aceitou e cujo início já passou → EXPIRADO.
 *  - Turno ABERTO parcialmente preenchido cujo início já passou → ACEITO
 *    (fecha as vagas remanescentes; quem já entrou continua valendo).
 *  - Turno ACEITO/EM_ANDAMENTO cujo fim já passou → NÃO muda de status.
 *    Finalizar dispara transação e pagamento; isso é decisão humana, o job só
 *    cobra o lojista via notificação.
 *
 * <p><b>Com réplica, os jobs rodariam em todas as instâncias.</b> Hoje isso é
 * inofensivo — {@code criarUnica} deduplica a notificação, e as mudanças de
 * status são idempotentes —, mas o trabalho seria feito N vezes. Enquanto não
 * houver um lock distribuído (ShedLock e uma tabela própria), a saída é
 * operacional e está aqui, explícita: subir as réplicas com
 * {@code MOTOSHIFT_JOBS_HABILITADOS=false} e deixar uma só instância com os
 * jobs ligados.
 */
@Service
@ConditionalOnProperty(name = "motoshift.jobs.habilitados", havingValue = "true", matchIfMissing = true)
public class TurnoExpiracaoService {

    private static final Logger log = LoggerFactory.getLogger(TurnoExpiracaoService.class);

    /**
     * Até quando o job cobra a finalização de um turno vencido.
     *
     * Nada tira o turno de ACEITO/EM_ANDAMENTO a não ser um humano finalizar,
     * então "todo turno com fim no passado" é um conjunto que só cresce e era
     * reprocessado a cada 5 minutos, para sempre. A notificação não se repetia
     * (criarUnica), mas o trabalho sim. Sete dias depois do fim, quem não
     * finalizou não vai finalizar por causa deste lembrete.
     */
    private static final int JANELA_DE_COBRANCA_DIAS = 7;

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;

    public TurnoExpiracaoService(TurnoRepository turnoRepo,
                                 TurnoInscricaoRepository inscricaoRepo,
                                 NotificacaoService notificacoes) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
    }

    /** Turnos abertos cujo horário de início já passou. */
    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void expirarTurnosNaoPreenchidos() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> candidatos = turnoRepo.findByStatusAndDataInicioBefore(StatusTurno.ABERTO, agora);
        Map<Long, Long> ocupacao = ocupacaoDe(candidatos);
        int expirados = 0, fechados = 0;

        for (Turno t : candidatos) {
            long ativas = ocupacao.getOrDefault(t.getId(), 0L);

            if (ativas == 0) {
                t.setStatus(StatusTurno.EXPIRADO);
                t.setExpiradoEm(agora);
                turnoRepo.save(t);
                expirados++;
                notificacoes.criarUnica(t.getLojistId(), "turno_expirado",
                        "Turno expirou sem entregador",
                        "O turno \"" + t.getTitulo() + "\" venceu sem ninguem aceitar. "
                                + "Republique com mais antecedencia ou revise o valor.",
                        "turno", t.getId());
            } else {
                // Parcialmente preenchido: fecha para novos aceites, mas o turno vale.
                t.setStatus(StatusTurno.ACEITO);
                turnoRepo.save(t);
                fechados++;
                notificacoes.criarUnica(t.getLojistId(), "turno_lotado",
                        "Turno iniciado com vagas em aberto",
                        "O turno \"" + t.getTitulo() + "\" comecou com " + ativas
                                + " de " + t.getVagas() + " vagas preenchidas.",
                        "turno", t.getId());
            }
        }
        if (expirados > 0 || fechados > 0) {
            log.info("[expiracao] {} turnos expirados, {} fechados por inicio", expirados, fechados);
        }
    }

    /** Aviso 1h antes: turno ainda aberto e com vaga sobrando. */
    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void avisarTurnosProximosDoVencimento() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> proximos = turnoRepo.findByStatusAndDataInicioBetween(
                StatusTurno.ABERTO, agora, agora.plusHours(1));
        Map<Long, Long> ocupacao = ocupacaoDe(proximos);

        for (Turno t : proximos) {
            long ativas = ocupacao.getOrDefault(t.getId(), 0L);
            if (ativas >= t.getVagas()) continue;
            notificacoes.criarUnica(t.getLojistId(), "turno_vencendo",
                    "Turno comeca em menos de 1 hora",
                    "O turno \"" + t.getTitulo() + "\" ainda tem "
                            + (t.getVagas() - ativas) + " vaga(s) em aberto.",
                    "turno", t.getId());
        }
    }

    /** Turno que já terminou e ninguém finalizou: cobra o lojista. */
    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void cobrarFinalizacaoPendente() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> vencidos = turnoRepo.findByStatusInAndDataFimBetween(
                List.of(StatusTurno.ACEITO, StatusTurno.EM_ANDAMENTO),
                agora.minusDays(JANELA_DE_COBRANCA_DIAS), agora);
        if (vencidos.isEmpty()) return;

        // Os entregadores de todos os turnos de uma vez, e não uma consulta por
        // turno dentro do laço.
        Map<Long, List<TurnoInscricao>> porTurno = new HashMap<>();
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdInAndStatus(
                vencidos.stream().map(Turno::getId).toList(), StatusInscricao.ACEITO)) {
            porTurno.computeIfAbsent(ins.getTurnoId(), k -> new ArrayList<>()).add(ins);
        }

        for (Turno t : vencidos) {
            notificacoes.criarUnica(t.getLojistId(), "turno_pendente_finalizacao",
                    "Turno terminou e aguarda finalizacao",
                    "O turno \"" + t.getTitulo() + "\" ja terminou. "
                            + "Finalize para liberar o pagamento dos entregadores.",
                    "turno", t.getId());

            for (TurnoInscricao ins : porTurno.getOrDefault(t.getId(), List.of())) {
                notificacoes.criarUnica(ins.getMotoboyId(), "turno_pendente_finalizacao",
                        "Turno terminou",
                        "O turno \"" + t.getTitulo() + "\" terminou e aguarda a "
                                + "finalizacao do lojista.",
                        "turno", t.getId());
            }
        }
    }

    /** Inscrições ativas por turno, numa consulta para a leva inteira. */
    private Map<Long, Long> ocupacaoDe(List<Turno> turnos) {
        Map<Long, Long> ocupacao = new HashMap<>();
        if (turnos.isEmpty()) return ocupacao;
        for (ContagemPorTurno c : inscricaoRepo.contarPorTurno(
                turnos.stream().map(Turno::getId).toList(), StatusInscricao.ACEITO)) {
            ocupacao.put(c.turnoId(), c.total());
        }
        return ocupacao;
    }
}
