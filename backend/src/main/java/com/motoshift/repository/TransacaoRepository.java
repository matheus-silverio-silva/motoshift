package com.motoshift.repository;

import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface TransacaoRepository extends JpaRepository<Transacao, Long> {

    List<Transacao> findByUsuarioIdOrderByCriadoEmDesc(Long usuarioId);

    /** Extrato paginado — mesma ordem da versao sem pagina. */
    Page<Transacao> findByUsuarioIdOrderByCriadoEmDesc(Long usuarioId, Pageable pagina);

    /** Base da idempotencia: se a chave ja existe, a operacao ja aconteceu. */
    Optional<Transacao> findByIdempotencyKey(String idempotencyKey);

    boolean existsByIdempotencyKey(String idempotencyKey);

    /**
     * Soma dos lancamentos de um tipo e status a partir de uma data.
     *
     * O filtro de status nao e opcional: o pagamento de turno nasce pendente
     * na finalizacao, entao somar sem ele conta dinheiro que ainda nao foi
     * pago.
     *
     * COALESCE porque SUM sobre conjunto vazio devolve NULL, e saldo nenhum e
     * zero, nao ausencia de valor.
     */
    @Query("SELECT COALESCE(SUM(t.valor), 0) FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.tipo = :tipo "
         + "AND t.status = :status AND t.criadoEm >= :desde")
    BigDecimal somarPorTipoDesde(@Param("usuarioId") Long usuarioId,
                                 @Param("tipo") TipoTransacao tipo,
                                 @Param("status") StatusTransacao status,
                                 @Param("desde") LocalDateTime desde);

    /**
     * Total por mes, somado no banco — a base do grafico de ganhos.
     *
     * Antes o servico carregava TODAS as transacoes do usuario e filtrava mes
     * a mes num stream. O mesmo filtro de tipo e status do
     * {@link #somarPorTipoDesde}: o grafico e a serie historica do "ganhos do
     * mes", e as duas leituras nao podem discordar. Meses sem lancamento nao
     * voltam; quem monta a serie preenche com zero.
     */
    @Query("SELECT new com.motoshift.repository.GanhoMensal("
         + "  year(t.criadoEm), month(t.criadoEm), SUM(t.valor)) "
         + "FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.tipo = :tipo "
         + "AND t.status = :status AND t.criadoEm >= :desde "
         + "GROUP BY year(t.criadoEm), month(t.criadoEm)")
    List<GanhoMensal> somarPorMesDesde(@Param("usuarioId") Long usuarioId,
                                       @Param("tipo") TipoTransacao tipo,
                                       @Param("status") StatusTransacao status,
                                       @Param("desde") LocalDateTime desde);
}
