package com.motoshift.repository;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

public interface TurnoRepository extends JpaRepository<Turno, Long> {

    List<Turno> findByLojistId(Long lojistId);

    List<Turno> findByMotoboyId(Long motoboyId);

    List<Turno> findByStatus(StatusTurno status);

    // ── Listagens paginaveis ──────────────────────────────────────────────
    // Com Pageable.unpaged() devolvem tudo, como as versoes em List. A ordem
    // e explicita porque pagina sem ordem definida repete e pula linhas.

    Page<Turno> findByStatusOrderByDataInicioAsc(StatusTurno status, Pageable pagina);

    Page<Turno> findByLojistIdOrderByDataInicioDesc(Long lojistId, Pageable pagina);

    /**
     * Turnos de um entregador: os que ele tem como principal E os que ele
     * ocupa por inscricao (vaga extra de turno multi-vaga), numa consulta so.
     *
     * Antes eram tres buscas — principal, inscricoes aceitas, inscricoes
     * finalizadas — e um findById por inscricao para completar a lista.
     */
    @Query(value = "select t from Turno t where t.motoboyId = :motoboyId "
                 + "or t.id in (select i.turnoId from TurnoInscricao i "
                 + "            where i.motoboyId = :motoboyId and i.status in :status) "
                 + "order by t.dataInicio desc",
           countQuery = "select count(t) from Turno t where t.motoboyId = :motoboyId "
                 + "or t.id in (select i.turnoId from TurnoInscricao i "
                 + "            where i.motoboyId = :motoboyId and i.status in :status)")
    Page<Turno> findDoEntregador(@Param("motoboyId") Long motoboyId,
                                 @Param("status") Collection<StatusInscricao> statusDaInscricao,
                                 Pageable pagina);

    /**
     * O entregador ja tem inscricao ativa num turno que se sobrepoe ao alvo?
     *
     * Cobre o multi-vaga, em que o turno de origem pode continuar ABERTO. Era
     * um laco com findById por inscricao; agora e uma pergunta so ao banco.
     */
    @Query("select case when count(t) > 0 then true else false end from Turno t "
         + "where t.id <> :alvoId "
         + "and t.status <> com.motoshift.entity.StatusTurno.CANCELADO "
         + "and t.dataInicio < :fim and t.dataFim > :inicio "
         + "and t.id in (select i.turnoId from TurnoInscricao i "
         + "             where i.motoboyId = :motoboyId "
         + "             and i.status = com.motoshift.entity.StatusInscricao.ACEITO)")
    boolean existeConflitoDeAgenda(@Param("motoboyId") Long motoboyId,
                                   @Param("alvoId") Long alvoId,
                                   @Param("inicio") LocalDateTime inicio,
                                   @Param("fim") LocalDateTime fim);

    // RF05: verifica conflito de horário para o motoboy
    @Query("SELECT t FROM Turno t WHERE t.motoboyId = :motoboyId " +
           // Literal de enum qualificado, e nao a string: assim o valor passa
           // pelo StatusTurnoConverter na hora de montar o SQL. String crua
           // aqui deixaria a comparacao ao acaso da caixa que o dialeto usar.
           "AND t.status IN (com.motoshift.entity.StatusTurno.ACEITO, "
         + "                 com.motoshift.entity.StatusTurno.EM_ANDAMENTO) " +
           "AND t.dataInicio < :fim AND t.dataFim > :inicio")
    List<Turno> findConflitos(
            @Param("motoboyId") Long motoboyId,
            @Param("inicio") LocalDateTime inicio,
            @Param("fim") LocalDateTime fim);

    long countByLojistIdAndStatusIn(Long lojistId, List<StatusTurno> statuses);

    // Histórico de turnos finalizados pelo motoboy a partir de uma data
    List<Turno> findByMotoboyIdAndStatusAndDataInicioAfter(
            Long motoboyId, StatusTurno status, LocalDateTime inicio);

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
    @Query("SELECT t FROM Turno t WHERE t.status = com.motoshift.entity.StatusTurno.ABERTO " +
           "AND t.latitude IS NOT NULL AND t.longitude IS NOT NULL " +
           "AND t.latitude BETWEEN :latMin AND :latMax " +
           "AND t.longitude BETWEEN :lngMin AND :lngMax")
    List<Turno> findAbertosNaArea(
            @Param("latMin") double latMin, @Param("latMax") double latMax,
            @Param("lngMin") double lngMin, @Param("lngMax") double lngMax);

    // ── SCRUM-19: vencimento ──────────────────────────────────────────────
    // Turnos ainda abertos cujo horário de início já passou.
    List<Turno> findByStatusAndDataInicioBefore(StatusTurno status, LocalDateTime limite);

    // Turnos em andamento/aceitos cujo fim caiu dentro de uma janela e ninguém
    // finalizou. Janela, e não "antes de agora": ver cobrarFinalizacaoPendente.
    List<Turno> findByStatusInAndDataFimBetween(List<StatusTurno> statuses,
                                                LocalDateTime de, LocalDateTime ate);

    // Turnos que começam dentro de uma janela (aviso de "vai vencer").
    List<Turno> findByStatusAndDataInicioBetween(
            StatusTurno status, LocalDateTime de, LocalDateTime ate);
}
