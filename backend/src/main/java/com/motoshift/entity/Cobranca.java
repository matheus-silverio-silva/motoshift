package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Uma operacao no gateway de pagamento: recarga entrando ou saque saindo.
 *
 * <p><b>Por que uma tabela propria, e nao mais um campo em transacoes.</b> Sao
 * dois ciclos de vida diferentes. O lancamento do extrato e um fato consumado —
 * nasce e nao muda de valor. A cobranca e um pedido em aberto que o mundo de
 * fora ainda vai responder: o Pix pode nunca ser pago, o saque pode ser
 * recusado. Misturar os dois faria o extrato ter linhas que representam
 * intencao, e "saldo = soma do extrato" deixaria de valer.
 *
 * <p><b>O gateway e simulado</b> ({@code GatewayPagamentoSimulado}), atras da
 * interface {@code GatewayPagamento}. O codigo Pix e ficticio e a confirmacao
 * vem de um endpoint que imita o webhook. Trocar por um provedor real e
 * implementar a interface; nada aqui muda.
 */
@Entity
@Table(
    name = "cobrancas",
    indexes = {
        @Index(name = "ix_cobranca_usuario", columnList = "usuarioId, criadaEm")
    }
)
public class Cobranca {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Dono da operacao: quem recarrega ou quem saca. Sai do token, nunca do corpo. */
    @Column(nullable = false)
    private Long usuarioId;

    @Column(nullable = false)
    private TipoCobranca tipo;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valor;

    @Column(nullable = false)
    private StatusCobranca status = StatusCobranca.PENDENTE;

    /**
     * Copia-e-cola do Pix. Ficticio: e o que o gateway simulado devolve para a
     * tela ter o que mostrar. Em saque guarda a chave de destino.
     */
    @Column(length = 512)
    private String codigoPix;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadaEm;

    /** Quando o gateway respondeu — concluindo ou falhando. Null enquanto aberta. */
    private LocalDateTime concluidaEm;

    /**
     * Chave de idempotencia do PEDIDO (nao do lancamento).
     *
     * Duas recargas de R$ 100 no mesmo minuto sao duas cobrancas legitimas, por
     * isso a chave padrao carrega um UUID. Quando o cliente manda
     * {@code Idempotency-Key}, a chave vira deterministica e repetir o pedido
     * devolve a mesma cobranca em vez de abrir outra.
     *
     * Os lancamentos que esta cobranca gera tem chave propria, derivada do id
     * dela: {@code recarga:{id}}, {@code saque:{id}}, {@code estorno:saque:{id}}.
     */
    @Column(nullable = false, unique = true, length = 255)
    private String idempotencyKey;

    @PrePersist
    private void prePersist() {
        if (criadaEm == null) criadaEm = LocalDateTime.now();
        if (status == null) status = StatusCobranca.PENDENTE;
    }

    public Long getId() { return id; }

    public Long getUsuarioId() { return usuarioId; }
    public void setUsuarioId(Long usuarioId) { this.usuarioId = usuarioId; }

    public TipoCobranca getTipo() { return tipo; }
    public void setTipo(TipoCobranca tipo) { this.tipo = tipo; }

    public BigDecimal getValor() { return valor; }
    public void setValor(BigDecimal valor) { this.valor = valor; }

    public StatusCobranca getStatus() { return status; }
    public void setStatus(StatusCobranca status) { this.status = status; }

    public String getCodigoPix() { return codigoPix; }
    public void setCodigoPix(String codigoPix) { this.codigoPix = codigoPix; }

    public LocalDateTime getCriadaEm() { return criadaEm; }
    /** Uso restrito a massa de demonstracao, que data cobrancas no passado. */
    public void setCriadaEm(LocalDateTime criadaEm) { this.criadaEm = criadaEm; }

    public LocalDateTime getConcluidaEm() { return concluidaEm; }
    public void setConcluidaEm(LocalDateTime concluidaEm) { this.concluidaEm = concluidaEm; }

    public String getIdempotencyKey() { return idempotencyKey; }
    public void setIdempotencyKey(String idempotencyKey) { this.idempotencyKey = idempotencyKey; }
}
