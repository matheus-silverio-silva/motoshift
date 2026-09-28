package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.repository.Chegada;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;

/**
 * A reputação (score) do entregador: a regra e o que se mostra dela.
 *
 * <p><b>A regra (RF07).</b> Todo entregador começa em {@link #SCORE_INICIAL}
 * e perde {@link #PENALIDADE_CANCELAMENTO_TARDIO} a cada turno cancelado a
 * menos de 1h do início ({@code TurnoService.cancelar}), sem descer de zero.
 * O valor mora em {@code usuarios.score} e só a regra o altera — nem a massa
 * de demonstração o grava à mão.
 *
 * <p><b>O que se mostra.</b> Score é do entregador, e de mais ninguém: o
 * lojista não tem reputação a zelar por cancelamento, e o 5,0 fixo que ele
 * carregava nunca mudava. E um entregador sem histórico — nenhum turno
 * concluído, nenhum cancelado — não tem o que medir: o 5,0 dele é o ponto de
 * partida da conta, não uma reputação conquistada. Nos dois casos a API
 * devolve {@code null}, e o app diz "Novo na plataforma" em vez de
 * "5.00 — Excelente".
 */
@Component
public class Reputacao {

    /** Onde todo entregador começa. */
    public static final double SCORE_INICIAL = 5.0;

    /** Quanto custa cancelar com menos de 1h de antecedência (RF07). */
    public static final double PENALIDADE_CANCELAMENTO_TARDIO = 0.5;

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;

    public Reputacao(TurnoRepository turnoRepo, TurnoInscricaoRepository inscricaoRepo) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
    }

    /**
     * O score que as telas mostram: o do entregador com histórico, e
     * {@code null} para o lojista e para o entregador novo.
     */
    public Double scoreVisivel(Usuario u) {
        if (u == null || !"motoboy".equals(u.getTipo()) || u.getId() == null) return null;
        if (!temHistorico(u.getId())) return null;
        return u.getScore() == null ? SCORE_INICIAL : u.getScore();
    }

    /**
     * Já trabalhou (turno concluído, inclusive em vaga extra) ou já cancelou —
     * os dois eventos que a reputação mede.
     */
    public boolean temHistorico(Long motoboyId) {
        return turnoRepo.existsByMotoboyIdAndStatusIn(motoboyId,
                        List.of(StatusTurno.FINALIZADO, StatusTurno.CANCELADO))
                || inscricaoRepo.existsByMotoboyIdAndStatus(motoboyId, StatusInscricao.FINALIZADO);
    }

    // ── Pontualidade ────────────────────────────────────────────────────────

    /** Até quanto depois do início a chegada ainda conta como pontual. */
    public static final Duration TOLERANCIA_PONTUAL = Duration.ofMinutes(10);

    /** A janela da pontualidade: turnos que começaram nos últimos 90 dias. */
    public static final int JANELA_PONTUALIDADE_DIAS = 90;

    /**
     * Percentual de check-ins até {@link #TOLERANCIA_PONTUAL} depois do
     * início, nos turnos dos últimos {@link #JANELA_PONTUALIDADE_DIAS} dias.
     *
     * <p>Sem check-in na janela, o percentual é {@code null} — "Sem histórico"
     * na tela. Nunca 100%: 100% de nada é o mesmo número inventado que o score
     * 5,0 do entregador novo era, e que saiu do app pelo mesmo motivo.
     *
     * <p>Mede só quem fez check-in. Turno sem check-in (anterior à V16, ou em
     * que o entregador esqueceu de tocar "Cheguei") não entra na conta nem
     * como atraso: não há hora real a comparar.
     */
    public Pontualidade pontualidade(Long motoboyId) {
        if (motoboyId == null) return Pontualidade.SEM_HISTORICO;
        List<Chegada> chegadas = inscricaoRepo.chegadasDesde(motoboyId,
                LocalDateTime.now().minusDays(JANELA_PONTUALIDADE_DIAS));
        if (chegadas.isEmpty()) return Pontualidade.SEM_HISTORICO;

        long pontuais = chegadas.stream()
                .filter(c -> !c.checkinEm().isAfter(c.inicioDoTurno().plus(TOLERANCIA_PONTUAL)))
                .count();
        int percentual = (int) Math.round(100.0 * pontuais / chegadas.size());
        return new Pontualidade(percentual, chegadas.size());
    }

    /**
     * @param percentual 0 a 100, ou {@code null} sem check-in na janela
     * @param checkins   quantos check-ins entraram na conta
     */
    public record Pontualidade(Integer percentual, int checkins) {
        public static final Pontualidade SEM_HISTORICO = new Pontualidade(null, 0);
    }

    /** O score depois de um cancelamento tardio. */
    public static double penalizar(Double atual) {
        double base = atual == null ? SCORE_INICIAL : atual;
        return Math.max(0.0, base - PENALIDADE_CANCELAMENTO_TARDIO);
    }
}
