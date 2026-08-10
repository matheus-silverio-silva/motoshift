package com.motoshift.repository;

import com.motoshift.entity.TurnoInscricao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface TurnoInscricaoRepository extends JpaRepository<TurnoInscricao, Long> {

    List<TurnoInscricao> findByTurnoId(Long turnoId);

    List<TurnoInscricao> findByTurnoIdAndStatus(Long turnoId, String status);

    List<TurnoInscricao> findByMotoboyIdAndStatus(Long motoboyId, String status);

    long countByTurnoIdAndStatus(Long turnoId, String status);

    boolean existsByTurnoIdAndMotoboyIdAndStatus(Long turnoId, Long motoboyId, String status);

    Optional<TurnoInscricao> findByTurnoIdAndMotoboyId(Long turnoId, Long motoboyId);
}
