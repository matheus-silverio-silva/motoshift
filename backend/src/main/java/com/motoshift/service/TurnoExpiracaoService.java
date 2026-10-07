package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.ContagemPorTurno;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.service.TurnoService.FinalizacaoAutomatica;
import com.motoshift.service.ledger.Movimento.MotivoLiberacao;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Vencimento automático de turnos (SCRUM-19) e finalização automática do
 * turno esquecido (SCRUM-31).
 *
 * Regras deliberadas:
 *  - Turno ABERTO que ninguém aceitou e cujo início já passou → EXPIRADO, e a
 *    reserva volta inteira ao disponível do lojista.
 *  - Turno ABERTO parcialmente preenchido cujo início já passou → ACEITO, ou
 *    EM_ANDAMENTO se alguém já fez check-in (fecha as vagas remanescentes;
 *    quem já entrou continua valendo). A reserva
 *    permanece bloqueada: o turno vai acontecer, e o que sobrar das vagas
 *    vazias é devolvido na finalização, quando se sabe quem trabalhou.
 *  - Turno EM_ANDAMENTO nunca vence: o job de vencimento só olha turno ABERTO.
 *  - Turno ACEITO/EM_ANDAMENTO cujo fim já passou → primeiro o job COBRA a
 *    finalização por notificação: finalizar é decisão de quem estava lá.
 *    Passado o prazo de {@code motoshift.finalizacao.automatica-horas}
 *    (padrão 12) sem ninguém finalizar, o job finaliza sozinho — ver
 *    {@link #finalizarTurnosEsquecidos()}. Antes só cobrava, e bastava as duas
 *    partes esquecerem o turno para o dinheiro ficar reservado para sempre.
 *
 * <p><b>Estes jobs movem dinheiro</b> (a liberação da reserva e a liquidação),
 * então são lugares onde a colisão otimista na carteira é possível — o
 * lojista pode estar publicando outro turno no mesmo instante. O vencimento
 * roda numa transação só e, se a carteira for disputada, falha inteiro e a
 * próxima execução (5 minutos depois) refaz o trabalho; a finalização
 * automática fecha cada turno na própria transação, e o que falhar fica para
 * a próxima volta. Nos dois casos as chaves de idempotência garantem que o
 * que já foi movido não é movido de novo.
 *
 * <p><b>Este serviço existe sempre; quem o agenda, não.</b> Os
 * {@code @Scheduled} moram em {@link TurnoExpiracaoJobs}, que só é criado com
 * {@code motoshift.jobs.habilitados=true}. Eram a mesma classe, e a classe
 * inteira era condicional — mas a massa de demonstração depende deste serviço
 * (é ele que vence o turno sem entregador da história), então subir uma
 * réplica com {@code MOTOSHIFT_JOBS_HABILITADOS=false}, que é o que o
 * cabeçalho daquela classe manda fazer, derrubava o boot.
 */
@Service
public class TurnoExpiracaoService {

    private static final Logger log = LoggerFactory.getLogger(TurnoExpiracaoService.class);

    /**
     * Até quando o job cobra a finalização de um turno vencido.
     *
     * A janela existe porque "todo turno com fim no passado" era um conjunto
     * que só crescia e era reprocessado a cada 5 minutos, para sempre. Com a
     * finalização automática o turno sai de ACEITO/EM_ANDAMENTO sozinho depois
     * do prazo; a janela continua como teto para um prazo configurado grande
     * demais (ou para um turno que a finalização automática não consiga
     * fechar).
     */
    private static final int JANELA_DE_COBRANCA_DIAS = 7;

    private static final List<StatusTurno> ESPERANDO_FINALIZACAO =
            List.of(StatusTurno.ACEITO, StatusTurno.EM_ANDAMENTO);

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;
    private final PagamentoTurnoService pagamentos;
    private final TurnoService turnos;
    private final int finalizacaoAutomaticaHoras;

    public TurnoExpiracaoService(TurnoRepository turnoRepo,
                                 TurnoInscricaoRepository inscricaoRepo,
                                 NotificacaoService notificacoes,
                                 PagamentoTurnoService pagamentos,
                                 TurnoService turnos,
                                 @Value("${motoshift.finalizacao.automatica-horas:12}")
                                 int finalizacaoAutomaticaHoras) {
        if (finalizacaoAutomaticaHoras < 1) {
            // Zero finalizaria o turno no minuto em que ele termina, antes de
            // qualquer pessoa ter a chance de finalizar; negativo, antes do fim.
            throw new IllegalArgumentException(
                    "motoshift.finalizacao.automatica-horas deve ser 1 ou mais; veio "
                            + finalizacaoAutomaticaHoras);
        }
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
        this.pagamentos = pagamentos;
        this.turnos = turnos;
        this.finalizacaoAutomaticaHoras = finalizacaoAutomaticaHoras;
    }

    /** Turnos abertos cujo horário de início já passou. */
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
                // Ninguem aceitou: o dinheiro reservado na publicacao volta
                // inteiro ao disponivel do lojista. Sem isto, um turno que
                // expirou deixaria o saldo preso para sempre.
                pagamentos.liberarReserva(t, MotivoLiberacao.EXPIRACAO);
                turnoRepo.save(t);
                expirados++;
                notificacoes.criarUnica(t.getLojistId(), "turno_expirado",
                        "Turno expirou sem entregador",
                        "O turno \"" + t.getTitulo() + "\" venceu sem ninguem aceitar. "
                                + "Republique com mais antecedencia ou revise o valor.",
                        "turno", t.getId());
            } else {
                // Parcialmente preenchido: fecha para novos aceites, mas o turno
                // vale — e por isso a reserva CONTINUA bloqueada. O que sobrar
                // das vagas vazias volta na finalizacao (liberacao_reserva com
                // motivo "sobra"), que e quando se sabe quem trabalhou. Se
                // alguem ja fez check-in (ele abre 30 min antes), o turno ja
                // comecou de fato: vai direto a EM_ANDAMENTO.
                t.setStatus(inscricaoRepo.existsByTurnoIdAndCheckinEmIsNotNull(t.getId())
                        ? StatusTurno.EM_ANDAMENTO
                        : StatusTurno.ACEITO);
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
    @Transactional
    public void cobrarFinalizacaoPendente() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> vencidos = turnoRepo.findByStatusInAndDataFimBetween(
                ESPERANDO_FINALIZACAO,
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

    /**
     * Turno esquecido se finaliza sozinho (SCRUM-31).
     *
     * <p>Turno ACEITO ou EM_ANDAMENTO cujo fim passou há mais de
     * {@code motoshift.finalizacao.automatica-horas} é fechado pelo MESMO
     * caminho de quem toca "Finalizar" — {@link TurnoService#finalizarPeloSistema},
     * com as regras de pagamento da finalização: só recebe quem fez check-in.
     * Sem nenhum check-in, as inscrições viram FALTOU, a reserva volta inteira
     * e o turno vai para EXPIRADO.
     *
     * <p><b>Sem {@code @Transactional} aqui, de propósito.</b> Cada turno é
     * fechado na própria transação (a do {@code TurnoService}). Numa transação
     * só, um turno que não fechasse — a carteira disputada naquele instante,
     * um turno antigo sem lastro — desfaria o fechamento de todos os outros, e
     * faria isso de novo a cada 5 minutos. Assim o que falha é registrado no
     * log e fica para a próxima volta; os demais seguem.
     *
     * @return quantos turnos foram fechados nesta volta (pagos ou sem check-in)
     */
    public int finalizarTurnosEsquecidos() {
        LocalDateTime limite = LocalDateTime.now().minusHours(finalizacaoAutomaticaHoras);
        List<Long> esquecidos = turnoRepo.idsComFimAntesDe(ESPERANDO_FINALIZACAO, limite);

        int pagos = 0, semCheckin = 0;
        for (Long id : esquecidos) {
            try {
                FinalizacaoAutomatica r = turnos.finalizarPeloSistema(id, finalizacaoAutomaticaHoras);
                if (r == FinalizacaoAutomatica.PAGA) pagos++;
                else if (r == FinalizacaoAutomatica.SEM_CHECKIN) semCheckin++;
            } catch (RuntimeException e) {
                log.warn("[finalizacao-automatica] turno {} nao foi fechado nesta volta e sera "
                        + "tentado de novo: {}", id, e.getMessage());
            }
        }
        if (pagos > 0 || semCheckin > 0) {
            log.info("[finalizacao-automatica] {} turnos finalizados e pagos, {} encerrados sem "
                    + "check-in (prazo de {}h depois do fim)", pagos, semCheckin,
                    finalizacaoAutomaticaHoras);
        }
        return pagos + semCheckin;
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
