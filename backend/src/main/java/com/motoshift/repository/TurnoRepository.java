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

    // Agenda: turnos do usuário (como lojista ou motoboy) em um período
    @Query("SELECT t FROM Turno t WHERE " +
           "(t.lojistId = :usuarioId OR t.motoboyId = :usuarioId) " +
           "AND t.dataInicio >= :inicio AND t.dataInicio < :fim " +
           "ORDER BY t.dataInicio ASC")
    List<Turno> findByUsuarioAndPeriodo(
            @Param("usuarioId") Long usuarioId,
            @Param("inicio") LocalDateTime inicio,
            @Param("fim") LocalDateTime fim);

    // ── SCRUM-18: pré-filtro geográfico ───────────────────────────────────
    // Bounding box no banco (usa ix_turno_geo) para não carregar todos os
    // turnos abertos na memória; o refino exato por Haversine é feito depois.
    @Query("SELECT t FROM Turno t WHERE t.status = 'aberto' " +
           "AND t.latitude IS NOT NULL AND t.longitude IS NOT NULL " +
           "AND t.latitude BETWEEN :latMin AND :latMax " +
           "AND t.longitude BETWEEN :lngMin AND :lngMax")
    List<Turno> findAbertosNaArea(
            @Param("latMin") double latMin, @Param("latMax") double latMax,
            @Param("lngMin") double lngMin, @Param("lngMax") double lngMax);

    // ── SCRUM-19: vencimento ──────────────────────────────────────────────
    // Turnos ainda abertos cujo horário de início já passou.
    List<Turno> findByStatusAndDataInicioBefore(String status, LocalDateTime limite);

    // Turnos em andamento/aceitos cujo fim já passou e ninguém finalizou.
    List<Turno> findByStatusInAndDataFimBefore(List<String> statuses, LocalDateTime limite);

    // Turnos que começam dentro de uma janela (aviso de "vai vencer").
    List<Turno> findByStatusAndDataInicioBetween(
            String status, LocalDateTime de, LocalDateTime ate);
}
