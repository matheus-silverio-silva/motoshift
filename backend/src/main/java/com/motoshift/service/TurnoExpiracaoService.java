package com.motoshift.service;

import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

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
 */
@Service
public class TurnoExpiracaoService {

    private static final Logger log = LoggerFactory.getLogger(TurnoExpiracaoService.class);

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
        List<Turno> candidatos = turnoRepo.findByStatusAndDataInicioBefore("aberto", agora);
        int expirados = 0, fechados = 0;

        for (Turno t : candidatos) {
            long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), "aceito");

            if (ativas == 0) {
                t.setStatus("expirado");
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
                t.setStatus("aceito");
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
                "aberto", agora, agora.plusHours(1));

        for (Turno t : proximos) {
            long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), "aceito");
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
        List<Turno> vencidos = turnoRepo.findByStatusInAndDataFimBefore(
                List.of("aceito", "em_andamento"), agora);

        for (Turno t : vencidos) {
            notificacoes.criarUnica(t.getLojistId(), "turno_pendente_finalizacao",
                    "Turno terminou e aguarda finalizacao",
                    "O turno \"" + t.getTitulo() + "\" ja terminou. "
                            + "Finalize para liberar o pagamento dos entregadores.",
                    "turno", t.getId());

            for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdAndStatus(t.getId(), "aceito")) {
                notificacoes.criarUnica(ins.getMotoboyId(), "turno_pendente_finalizacao",
                        "Turno terminou",
                        "O turno \"" + t.getTitulo() + "\" terminou e aguarda a "
                                + "finalizacao do lojista.",
                        "turno", t.getId());
            }
        }
    }
}
