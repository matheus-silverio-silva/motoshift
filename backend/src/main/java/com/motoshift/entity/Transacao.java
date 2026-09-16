package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

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
        @Index(name = "ix_transacao_usuario", columnList = "usuarioId, criadoEm"),
        @Index(name = "ix_transacao_turno",   columnList = "turnoId")
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

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valor;

    private String descricao;

    @Column(nullable = false)
    private StatusTransacao status = StatusTransacao.CONCLUIDO;

    /**
     * Chave de idempotencia da operacao que gerou este lancamento.
     *
     * Unica: e ela que impede que a mesma operacao mova dinheiro duas vezes.
     * Obrigatoria desde a V10 — ate ali so alguns caminhos a preenchiam, e um
     * campo de garantia que depende de quem lembrou de preencher nao garante
     * nada. Formato por caminho:
     *   pagamento_turno:{turnoId}:{motoboyId}  pagamento de um entregador num turno
     *   saque:{usuarioId}:{chave do cliente}    saque com Idempotency-Key
     *   saque:{uuid}                            saque sem chave do cliente
     *   legado:{id}                             linha anterior a V10
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
