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

    Optional<TurnoInscricao> findByTurnoIdAndMotoboyId(Long turnoId, Long motoboyId);

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
