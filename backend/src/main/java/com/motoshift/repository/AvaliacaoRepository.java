package com.motoshift.repository;

import com.motoshift.entity.Avaliacao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AvaliacaoRepository extends JpaRepository<Avaliacao, Long> {

    List<Avaliacao> findByAvaliadoIdOrderByCriadoEmDesc(Long avaliadoId);

    /**
     * @deprecated trava o avaliador no primeiro alvo em turnos multi-vaga.
     *             Use {@link #existsByTurnoIdAndAvaliadorIdAndAvaliadoId}.
     */
    @Deprecated
    boolean existsByTurnoIdAndAvaliadorId(Long turnoId, Long avaliadorId);

    // Duplicata real: mesmo avaliador, mesmo turno, MESMO avaliado.
    boolean existsByTurnoIdAndAvaliadorIdAndAvaliadoId(
            Long turnoId, Long avaliadorId, Long avaliadoId);

    List<Avaliacao> findByTurnoIdAndAvaliadorId(Long turnoId, Long avaliadorId);

    List<Avaliacao> findByTurnoId(Long turnoId);

    List<Avaliacao> findByAvaliadorId(Long avaliadorId);
}
