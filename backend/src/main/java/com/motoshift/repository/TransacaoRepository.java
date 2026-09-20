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

public interface TransacaoRepository extends JpaRepository<Transacao, Long>,
        org.springframework.data.jpa.repository.JpaSpecificationExecutor<Transacao> {

    List<Transacao> findByUsuarioIdOrderByCriadoEmDesc(Long usuarioId);

    /** Todos os lancamentos de um turno — os dois lados da liquidacao inclusive. */
    List<Transacao> findByTurnoId(Long turnoId);

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

    /**
     * Entradas e saidas por DIA, somadas no banco — a base do grafico de fluxo.
     *
     * <p>Substitui o agrupamento em memoria do grafico antigo, que carregava o
     * extrato inteiro para separa-lo mes a mes num stream. O que sai daqui e no
     * maximo um registro por dia e natureza; quem quiser a serie por semana ou
     * por mes dobra esses baldes, e isso custa o tamanho do periodo, nao o
     * volume de lancamentos.
     *
     * <p>So lancamentos CONCLUIDOS: um grafico de fluxo de caixa que inclui
     * dinheiro que nao se moveu nao e um grafico de fluxo de caixa.
     */
    @Query("SELECT new com.motoshift.repository.PontoDeFluxo("
         + "  year(t.criadoEm), month(t.criadoEm), day(t.criadoEm), t.natureza, SUM(t.valor)) "
         + "FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.status = com.motoshift.entity.StatusTransacao.CONCLUIDO "
         + "AND t.criadoEm >= :inicio AND t.criadoEm < :fim "
         + "GROUP BY year(t.criadoEm), month(t.criadoEm), day(t.criadoEm), t.natureza "
         + "ORDER BY year(t.criadoEm), month(t.criadoEm), day(t.criadoEm)")
    List<PontoDeFluxo> fluxoPorDia(@Param("usuarioId") Long usuarioId,
                                   @Param("inicio") LocalDateTime inicio,
                                   @Param("fim") LocalDateTime fim);

    /** Quanto cada tipo somou no periodo — a quebra do resumo. */
    @Query("SELECT new com.motoshift.repository.TotalPorTipo(t.tipo, SUM(t.valor), COUNT(t)) "
         + "FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.status = com.motoshift.entity.StatusTransacao.CONCLUIDO "
         + "AND t.criadoEm >= :inicio AND t.criadoEm < :fim "
         + "GROUP BY t.tipo "
         + "ORDER BY SUM(t.valor) DESC")
    List<TotalPorTipo> totalPorTipo(@Param("usuarioId") Long usuarioId,
                                    @Param("inicio") LocalDateTime inicio,
                                    @Param("fim") LocalDateTime fim);

    /**
     * Soma por natureza no periodo — entradas e saidas do resumo.
     *
     * <p>Aqui a natureza e o criterio certo, e nao os deltas de saldo: o que se
     * pergunta e "quanto entrou e quanto saiu no extrato", que e a leitura do
     * usuario. Reserva e liberacao aparecem como saida e entrada porque e assim
     * que ele as ve na tela.
     */
    @Query("SELECT t.natureza, COALESCE(SUM(t.valor), 0) FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.status = com.motoshift.entity.StatusTransacao.CONCLUIDO "
         + "AND t.criadoEm >= :inicio AND t.criadoEm < :fim "
         + "GROUP BY t.natureza")
    List<Object[]> somarPorNatureza(@Param("usuarioId") Long usuarioId,
                                    @Param("inicio") LocalDateTime inicio,
                                    @Param("fim") LocalDateTime fim);

    /**
     * O que cada turno ainda mantem bloqueado na carteira do lojista.
     *
     * <p>Reserva menos o que ja saiu dela — pagamentos e liberacoes —, com os
     * sinais vindo do tipo. So aparece turno com saldo remanescente: um turno
     * ja liquidado por inteiro some da lista em vez de figurar com zero.
     */
    @Query("SELECT new com.motoshift.repository.ReservaAberta(t.turnoId, MAX(tu.titulo), "
         + "  SUM(CASE WHEN t.tipo = com.motoshift.entity.TipoTransacao.RESERVA THEN t.valor "
         + "           ELSE -t.valor END)) "
         + "FROM Transacao t JOIN Turno tu ON tu.id = t.turnoId "
         + "WHERE t.usuarioId = :usuarioId "
         + "AND t.status = com.motoshift.entity.StatusTransacao.CONCLUIDO "
         + "AND t.tipo IN (com.motoshift.entity.TipoTransacao.RESERVA, "
         + "               com.motoshift.entity.TipoTransacao.LIBERACAO_RESERVA, "
         + "               com.motoshift.entity.TipoTransacao.PAGAMENTO_ENVIADO) "
         + "GROUP BY t.turnoId "
         + "HAVING SUM(CASE WHEN t.tipo = com.motoshift.entity.TipoTransacao.RESERVA THEN t.valor "
         + "                ELSE -t.valor END) > 0 "
         + "ORDER BY t.turnoId")
    List<ReservaAberta> reservasAbertas(@Param("usuarioId") Long usuarioId);

    /**
     * Lancamentos de um tipo no periodo, com o turno que os originou ao lado.
     *
     * <p>Base dos relatorios: a apuracao passou a sair do EXTRATO e nao mais de
     * Turno.valorEstimado. A diferenca nao e de estilo — valorEstimado e o que
     * o turno PROMETIA pagar por entregador, e o relatorio precisa do que foi
     * de fato pago. Num turno de tres vagas com dois inscritos, o primeiro diz
     * 120 e o segundo diz 240, e so um dos dois e a resposta certa para "quanto
     * este lojista gastou".
     *
     * <p>LEFT JOIN porque nem todo lancamento tem turno, e mesmo os que tem
     * podem apontar para um turno apagado — o relatorio nao pode sumir com uma
     * linha de dinheiro por causa disso.
     */
    @Query("SELECT t, tu FROM Transacao t LEFT JOIN Turno tu ON tu.id = t.turnoId "
         + "WHERE t.usuarioId = :usuarioId AND t.tipo = :tipo "
         + "AND t.status = com.motoshift.entity.StatusTransacao.CONCLUIDO "
         + "AND t.criadoEm >= :inicio AND t.criadoEm < :fim "
         + "ORDER BY t.criadoEm")
    List<Object[]> lancamentosComTurno(@Param("usuarioId") Long usuarioId,
                                       @Param("tipo") TipoTransacao tipo,
                                       @Param("inicio") LocalDateTime inicio,
                                       @Param("fim") LocalDateTime fim);

    /** Soma simples de um tipo no periodo — usada nos totais dos relatorios. */
    @Query("SELECT COALESCE(SUM(t.valor), 0) FROM Transacao t "
         + "WHERE t.usuarioId = :usuarioId AND t.tipo = :tipo "
         + "AND t.status = com.motoshift.entity.StatusTransacao.CONCLUIDO "
         + "AND t.criadoEm >= :inicio AND t.criadoEm < :fim")
    BigDecimal somarTipoNoPeriodo(@Param("usuarioId") Long usuarioId,
                                  @Param("tipo") TipoTransacao tipo,
                                  @Param("inicio") LocalDateTime inicio,
                                  @Param("fim") LocalDateTime fim);
}
