package com.motoshift.repository;

import com.motoshift.entity.Turno;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface TurnoRepository extends JpaRepository<Turno, Long> {

    List<Turno> findByLojistId(Long lojistId);

    List<Turno> findByMotoboyId(Long motoboyId);

    List<Turno> findByStatus(String status);

    // RF05: verifica conflito de horário para o motoboy
    @Query("SELECT t FROM Turno t WHERE t.motoboyId = :motoboyId " +
           "AND t.status IN ('aceito', 'em_andamento') " +
           "AND t.dataInicio < :fim AND t.dataFim > :inicio")
    List<Turno> findConflitos(
            @Param("motoboyId") Long motoboyId,
            @Param("inicio") LocalDateTime inicio,
            @Param("fim") LocalDateTime fim);

    long countByLojistIdAndStatusIn(Long lojistId, List<String> statuses);

    // Histórico de turnos finalizados pelo motoboy a partir de uma data
    List<Turno> findByMotoboyIdAndStatusAndDataInicioAfter(
            Long motoboyId, String status, LocalDateTime inicio);
}
