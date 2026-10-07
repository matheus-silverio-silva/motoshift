package com.motoshift.repository;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface TurnoRepository extends JpaRepository<Turno, Long> {

    /**
     * O turno, com a linha travada ate o fim da transacao (SELECT ... FOR
     * UPDATE). So para quem mexe na ocupacao das vagas: aceitar e desistir.
     *
     * <p>O aceite conta as inscricoes e grava em seguida. Sem trava, dois
     * entregadores que tocassem "Aceitar" na ultima vaga ao mesmo tempo liam
     * os dois "0 de 1 ocupada" e entravam os dois — a unicidade da inscricao
     * e por (turno, entregador), entao nao barrava. Com a linha do turno
     * travada, o segundo espera o primeiro commitar e ja le o turno lotado.
     *
     * <p>Pessimista, e nao {@code @Version}: a disputa pela ultima vaga e o
     * caso esperado, nao a excecao, e a resposta certa para quem perdeu e um
     * 409 "vagas preenchidas" — nao um erro de concorrencia para repetir. E a
     * finalizacao e o cancelamento, que tambem gravam o turno, nao passam a
     * falhar por causa de um aceite simultaneo.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from Turno t where t.id = :id")
    Optional<Turno> buscarTravandoAsVagas(@Param("id") Long id);

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
     * RF05 — o entregador ja tem inscricao ativa num turno que se sobrepoe ao
     * alvo?
     *
     * Substitui o findConflitos, que olhava turnos.motoboy_id e so status
     * ACEITO/EM_ANDAMENTO: num turno multi-vaga o entregador entra pela
     * inscricao e o turno continua ABERTO, entao o conflito escapava. Tambem
     * substitui o laco com um findById por inscricao ativa que veio depois.
     *
     * Literal de enum qualificado, e nao string: assim o valor passa pelos
     * converters na hora de montar o SQL.
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

    long countByLojistIdAndStatusIn(Long lojistId, List<StatusTurno> statuses);

    /** Se o entregador já tem turno encerrado — a base de "tem histórico". */
    boolean existsByMotoboyIdAndStatusIn(Long motoboyId, List<StatusTurno> statuses);

    // existsByCanceladoPorIdAndCanceladoEmAfter saiu daqui: o selo "30 dias sem
    // cancelar" lê a desistência na inscrição (V22). turnos.cancelado_por_id
    // passou a dizer só quem cancelou o TURNO, e esse é sempre o lojista.

    /** Inícios dos turnos da loja num status, desde uma data — o selo "Contrata toda semana". */
    @Query("select t.dataInicio from Turno t where t.lojistId = :lojistaId "
            + "and t.status = :status and t.dataInicio >= :desde")
    List<LocalDateTime> iniciosDosTurnosDaLojaDesde(@Param("lojistaId") Long lojistaId,
                                                   @Param("status") StatusTurno status,
                                                   @Param("desde") LocalDateTime desde);

    /** Turnos que começam numa janela, em qualquer dos status — o lembrete de 1 h. */
    List<Turno> findByStatusInAndDataInicioBetween(List<StatusTurno> statuses,
                                                   LocalDateTime de, LocalDateTime ate);

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

    // Turnos aceitos ou em andamento cujo fim passou do prazo — os que a
    // finalizacao automatica fecha. So os ids: cada um e fechado na propria
    // transacao, e carrega-lo aqui o prenderia a esta.
    @Query("select t.id from Turno t where t.status in :statuses and t.dataFim < :limite "
         + "order by t.dataFim asc")
    List<Long> idsComFimAntesDe(@Param("statuses") List<StatusTurno> statuses,
                                @Param("limite") LocalDateTime limite);

    // Turnos que começam dentro de uma janela (aviso de "vai vencer").
    List<Turno> findByStatusAndDataInicioBetween(
            StatusTurno status, LocalDateTime de, LocalDateTime ate);
}
