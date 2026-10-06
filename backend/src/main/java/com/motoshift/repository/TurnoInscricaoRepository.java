package com.motoshift.repository;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.TurnoInscricao;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface TurnoInscricaoRepository extends JpaRepository<TurnoInscricao, Long> {

    List<TurnoInscricao> findByTurnoId(Long turnoId);

    List<TurnoInscricao> findByTurnoIdAndStatus(Long turnoId, StatusInscricao status);

    List<TurnoInscricao> findByMotoboyIdAndStatus(Long motoboyId, StatusInscricao status);

    long countByTurnoIdAndStatus(Long turnoId, StatusInscricao status);

    boolean existsByTurnoIdAndMotoboyIdAndStatus(Long turnoId, Long motoboyId, StatusInscricao status);

    /** Trabalhou em algum turno, inclusive em vaga extra. */
    boolean existsByMotoboyIdAndStatus(Long motoboyId, StatusInscricao status);

    /** Turnos concluídos pelo entregador — o selo "25 turnos concluídos". */
    long countByMotoboyIdAndStatus(Long motoboyId, StatusInscricao status);

    /** Início do primeiro turno que o entregador concluiu — o selo "30 dias sem cancelar". */
    @Query("select min(t.dataInicio) from TurnoInscricao i, Turno t "
            + "where i.turnoId = t.id and i.motoboyId = :motoboyId "
            + "and i.status = com.motoshift.entity.StatusInscricao.FINALIZADO")
    java.time.LocalDateTime primeiroTurnoConcluido(@Param("motoboyId") Long motoboyId);

    Optional<TurnoInscricao> findByTurnoIdAndMotoboyId(Long turnoId, Long motoboyId);

    /** Alguém já chegou? Turno com check-in já começou, mesmo que o status diga outra coisa. */
    boolean existsByTurnoIdAndCheckinEmIsNotNull(Long turnoId);

    /**
     * Alguma inscricao neste status ja fez check-in? Com ACEITO, e a pergunta
     * da finalizacao: sem check-in de quem ainda esta no turno, nao ha quem
     * pagar.
     */
    boolean existsByTurnoIdAndStatusAndCheckinEmIsNotNull(Long turnoId, StatusInscricao status);

    /**
     * Dos turnos pedidos, os que tem check-in — o {@code algumCheckin} das
     * listagens, numa consulta so.
     */
    @Query("select distinct i.turnoId from TurnoInscricao i "
         + "where i.turnoId in :turnos and i.checkinEm is not null")
    List<Long> turnosComCheckin(@Param("turnos") Collection<Long> turnoIds);

    /**
     * As chegadas do entregador a turnos que começaram desde [desde] — a base
     * da pontualidade. Uma linha por check-in, com a hora marcada ao lado.
     */
    @Query("select new com.motoshift.repository.Chegada(i.checkinEm, t.dataInicio) "
         + "from TurnoInscricao i, Turno t "
         + "where t.id = i.turnoId and i.motoboyId = :motoboyId "
         + "and i.checkinEm is not null and t.dataInicio >= :desde")
    List<Chegada> chegadasDesde(@Param("motoboyId") Long motoboyId,
                                @Param("desde") java.time.LocalDateTime desde);

    // ── Em lote ─────────────────────────────────────────────────────────────
    // As listagens montavam cada turno com uma consulta propria (N turnos, N+1
    // queries). Estas buscam o conjunto inteiro de uma vez. Quem chama nao
    // passa colecao vazia — IN () nao e SQL valido em todo banco.

    List<TurnoInscricao> findByTurnoIdIn(Collection<Long> turnoIds);

    List<TurnoInscricao> findByTurnoIdInAndStatus(Collection<Long> turnoIds, StatusInscricao status);

    @Query("select new com.motoshift.repository.ContagemPorTurno(i.turnoId, count(i)) "
         + "from TurnoInscricao i "
         + "where i.turnoId in :turnos and i.status = :status "
         + "group by i.turnoId")
    List<ContagemPorTurno> contarPorTurno(@Param("turnos") Collection<Long> turnoIds,
                                          @Param("status") StatusInscricao status);
}
