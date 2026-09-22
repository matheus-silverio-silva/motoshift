package com.motoshift.repository;

import com.motoshift.entity.Cobranca;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.TipoCobranca;
import org.springframework.data.jpa.repository.JpaRepository;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface CobrancaRepository extends JpaRepository<Cobranca, Long> {

    /** Base da idempotencia do PEDIDO: mesma chave, mesma cobranca. */
    Optional<Cobranca> findByIdempotencyKey(String idempotencyKey);

    /** Cobrancas do usuario, da mais recente para a mais antiga. */
    List<Cobranca> findByUsuarioIdOrderByCriadaEmDesc(Long usuarioId);

    /** Recargas ou saques de um periodo — usado pelos relatorios. */
    List<Cobranca> findByUsuarioIdAndTipoAndStatusAndCriadaEmBetween(
            Long usuarioId, TipoCobranca tipo, StatusCobranca status,
            LocalDateTime inicio, LocalDateTime fim);

    /**
     * Soma das cobrancas de um tipo e status num periodo.
     *
     * COALESCE porque SUM de conjunto vazio devolve NULL, e "nenhuma recarga" e
     * zero, nao ausencia de valor.
     */
    @org.springframework.data.jpa.repository.Query(
            "SELECT COALESCE(SUM(c.valor), 0) FROM Cobranca c "
          + "WHERE c.usuarioId = :usuarioId AND c.tipo = :tipo AND c.status = :status "
          + "AND c.criadaEm >= :inicio AND c.criadaEm < :fim")
    BigDecimal somar(@org.springframework.data.repository.query.Param("usuarioId") Long usuarioId,
                     @org.springframework.data.repository.query.Param("tipo") TipoCobranca tipo,
                     @org.springframework.data.repository.query.Param("status") StatusCobranca status,
                     @org.springframework.data.repository.query.Param("inicio") LocalDateTime inicio,
                     @org.springframework.data.repository.query.Param("fim") LocalDateTime fim);
}
