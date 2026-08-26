package com.motoshift.repository;

import com.motoshift.entity.Transacao;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface TransacaoRepository extends JpaRepository<Transacao, Long> {

    List<Transacao> findByUsuarioIdOrderByCriadoEmDesc(Long usuarioId);

    List<Transacao> findByUsuarioIdAndTipoInOrderByCriadoEmDesc(Long usuarioId, Collection<String> tipos);

    /** Base da idempotencia: se a chave ja existe, a operacao ja aconteceu. */
    Optional<Transacao> findByIdempotencyKey(String idempotencyKey);

    boolean existsByIdempotencyKey(String idempotencyKey);

    /**
     * Soma dos lancamentos de um tipo a partir de uma data.
     *
     * COALESCE porque SUM sobre conjunto vazio devolve NULL, e saldo nenhum e
     * zero, nao ausencia de valor.
     */
    @Query("SELECT COALESCE(SUM(t.valor), 0) FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.tipo IN :tipos AND t.criadoEm >= :desde")
    BigDecimal somarPorTipoDesde(@Param("usuarioId") Long usuarioId,
                                 @Param("tipos") Collection<String> tipos,
                                 @Param("desde") LocalDateTime desde);
}
