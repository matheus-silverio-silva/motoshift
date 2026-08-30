package com.motoshift.repository;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.TurnoInscricao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface TurnoInscricaoRepository extends JpaRepository<TurnoInscricao, Long> {

    List<TurnoInscricao> findByTurnoId(Long turnoId);

    List<TurnoInscricao> findByTurnoIdAndStatus(Long turnoId, StatusInscricao status);

    List<TurnoInscricao> findByMotoboyIdAndStatus(Long motoboyId, StatusInscricao status);

    long countByTurnoIdAndStatus(Long turnoId, StatusInscricao status);

    boolean existsByTurnoIdAndMotoboyIdAndStatus(Long turnoId, Long motoboyId, StatusInscricao status);

    Optional<TurnoInscricao> findByTurnoIdAndMotoboyId(Long turnoId, Long motoboyId);
}
