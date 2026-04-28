package com.motoshift.repository;

import com.motoshift.entity.Avaliacao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AvaliacaoRepository extends JpaRepository<Avaliacao, Long> {

    List<Avaliacao> findByAvaliadoIdOrderByCriadoEmDesc(Long avaliadoId);

    boolean existsByTurnoIdAndAvaliadorId(Long turnoId, Long avaliadorId);

    List<Avaliacao> findByTurnoId(Long turnoId);
}
