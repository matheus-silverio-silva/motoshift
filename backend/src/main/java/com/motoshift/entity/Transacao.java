package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Lancamento no extrato de um usuario.
 *
 * Toda alteracao de saldo tem uma Transacao correspondente — o extrato e a
 * fonte da verdade sobre o que aconteceu com o dinheiro; o saldo na Carteira
 * e so o acumulado.
 */
@Entity
@Table(
    name = "transacoes",
    indexes = {
        @Index(name = "ix_transacao_usuario",      columnList = "usuarioId, criadoEm"),
        @Index(name = "ix_transacao_turno",        columnList = "turnoId"),
        // Extrato filtrado por tipo e o corte mais usado depois do periodo.
        @Index(name = "ix_transacao_usuario_tipo", columnList = "usuarioId, tipo, criadoEm"),
        // Recuperar os dois lados de uma transferencia a partir de um deles.
        @Index(name = "ix_transacao_operacao",     columnList = "operacaoId")
    }
)
public class Transacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Dono da transacao — de quem e este lancamento no extrato. */
    @Column(nullable = false)
    private Long usuarioId;

    /**
     * O outro lado da operacao: no pagamento de um turno, o lojista aponta
     * para o entregador e vice-versa. Null em operacoes de uma ponta so
     * (recarga, saque, bonus).
     */
    private Long contraparteId;

    /**
     * @deprecated Legado. Substituido por {@link #usuarioId}. Nullable desde a
     * V4 porque transacao de lojista nao tem motoboy dono.
     */
    @Deprecated
    private Long motoboyId;

    private Long turnoId;

    /** Valores no banco em minusculo; a traducao e do TipoTransacaoConverter. */
    @Column(nullable = false)
    private TipoTransacao tipo;

    /**
     * Se este lancamento entra ou sai, gravado em vez de deduzido.
     *
     * O app desenhava o sinal a partir de uma lista de tipos, entao um tipo que
     * a versao instalada nao conhecesse virava credito por omissao. Com a
     * coluna, o sinal e o mesmo no backend, no CSV exportado e em qualquer
     * versao do cliente. Ver {@link NaturezaTransacao} — em particular, por que
     * somar por ela NAO devolve o saldo.
     */
    @Column(nullable = false)
    private NaturezaTransacao natureza;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valor;

    private String descricao;

    @Column(nullable = false)
    private StatusTransacao status = StatusTransacao.CONCLUIDO;

    /**
     * Agrupa os dois lados de uma transferencia.
     *
     * Quando um turno liquida, o lojista recebe um {@code pagamento_enviado} e o
     * entregador um {@code pagamento_recebido}: duas linhas, em dois extratos,
     * que sao o mesmo evento. Sem isto, ligar uma a outra so daria por
     * aproximacao (mesmo turno, mesmo valor, horario parecido) — que erra
     * justamente no caso que importa, dois entregadores pelo mesmo valor no
     * mesmo turno.
     *
     * Null em operacao de uma ponta so (recarga, saque, reserva, liberacao).
     * Sem FK: aponta para um agrupamento logico, nao para uma tabela.
     */
    private UUID operacaoId;

    /**
     * Saldo da carteira logo depois deste lancamento — os dois bolsos.
     *
     * Existe para o extrato mostrar "saldo apos" linha a linha sem refazer a
     * soma do zero, e para que uma divergencia entre carteira e extrato possa
     * ser localizada no lancamento exato em que comecou.
     *
     * Null nas linhas anteriores a V12: o saldo daquele momento nao e
     * reconstruivel, e inventar um numero seria pior do que admitir a lacuna.
     */
    @Column(precision = 12, scale = 2)
    private BigDecimal saldoDisponivelApos;

    @Column(precision = 12, scale = 2)
    private BigDecimal saldoBloqueadoApos;

    /**
     * Chave de idempotencia da operacao que gerou este lancamento.
     *
     * Unica: e ela que impede que a mesma operacao mova dinheiro duas vezes.
     * Obrigatoria desde a V10 — ate ali so alguns caminhos a preenchiam, e um
     * campo de garantia que depende de quem lembrou de preencher nao garante
     * nada. Desde a V12 ela e DETERMINISTICA em todo lancamento: nao ha mais
     * chave com UUID no extrato, entao repetir a operacao nunca move dinheiro
     * de novo — o ledger reencontra o lancamento anterior e devolve o mesmo
     * resultado. Formato por caminho:
     *   recarga:{cobrancaId}                        credito da recarga paga
     *   saque:{cobrancaId}                          debito do saque
     *   estorno:saque:{cobrancaId}                  devolucao de saque recusado
     *   reserva:turno:{turnoId}                     bloqueio ao publicar
     *   liberacao:turno:{turnoId}:{motivo}          cancelamento | expiracao | sobra
     *   liquidacao:inscricao:{inscricaoId}:debito   lado do lojista
     *   liquidacao:inscricao:{inscricaoId}:credito  lado do entregador
     *   liquidacao:turno:{turnoId}:{motoboyId}:...  turno sem inscricao (pre-V5)
     *   pagamento_turno:{turnoId}:{motoboyId}       legado (V10), antes da V12
     *   legado:{id}                                 linha anterior a V10
     *
     * Os dois lados de uma transferencia sao lancamentos distintos e por isso
     * precisam de chaves distintas — dai o sufixo. O que os une e o
     * {@link #operacaoId}.
     */
    @Column(nullable = false, unique = true)
    private String idempotencyKey;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        // So a massa de demonstracao data um lancamento no passado (para o
        // grafico mensal ter mais de uma barra). O fluxo normal deixa null e o
        // carimbo e sempre "agora".
        if (criadoEm == null) criadoEm = LocalDateTime.now();
        if (status == null) status = StatusTransacao.CONCLUIDO;
    }

    public NaturezaTransacao getNatureza() { return natureza; }
    public void setNatureza(NaturezaTransacao natureza) { this.natureza = natureza; }

    public UUID getOperacaoId() { return operacaoId; }
    public void setOperacaoId(UUID operacaoId) { this.operacaoId = operacaoId; }

    public BigDecimal getSaldoDisponivelApos() { return saldoDisponivelApos; }
    public void setSaldoDisponivelApos(BigDecimal v) { this.saldoDisponivelApos = v; }

    public BigDecimal getSaldoBloqueadoApos() { return saldoBloqueadoApos; }
    public void setSaldoBloqueadoApos(BigDecimal v) { this.saldoBloqueadoApos = v; }

    public Long getId() { return id; }

    public Long getUsuarioId() { return usuarioId; }
    public void setUsuarioId(Long usuarioId) { this.usuarioId = usuarioId; }

    public Long getContraparteId() { return contraparteId; }
    public void setContraparteId(Long contraparteId) { this.contraparteId = contraparteId; }

    /** @deprecated use {@link #getUsuarioId()}. */
    @Deprecated
    public Long getMotoboyId() { return motoboyId; }

    /** @deprecated use {@link #setUsuarioId(Long)}. */
    @Deprecated
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public TipoTransacao getTipo() { return tipo; }
    public void setTipo(TipoTransacao tipo) { this.tipo = tipo; }

    public BigDecimal getValor() { return valor; }
    public void setValor(BigDecimal valor) { this.valor = valor; }

    public String getDescricao() { return descricao; }
    public void setDescricao(String descricao) { this.descricao = descricao; }

    public StatusTransacao getStatus() { return status; }
    public void setStatus(StatusTransacao status) { this.status = status; }

    public String getIdempotencyKey() { return idempotencyKey; }
    public void setIdempotencyKey(String idempotencyKey) { this.idempotencyKey = idempotencyKey; }

    public LocalDateTime getCriadoEm() { return criadoEm; }

    /** Ver o comentario do @PrePersist: uso restrito a massa de demonstracao. */
    public void setCriadoEm(LocalDateTime criadoEm) { this.criadoEm = criadoEm; }
}
