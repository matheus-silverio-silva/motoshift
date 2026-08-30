package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Carteira de um usuario da plataforma — lojista ou entregador.
 *
 * O saldo e dividido em duas partes:
 *   saldoDisponivel — pode ser gasto ou sacado agora
 *   saldoBloqueado  — reservado para turnos ja publicados, ainda nao liquidados
 *
 * A soma das duas e o patrimonio do usuario na plataforma. Publicar um turno
 * move dinheiro de disponivel para bloqueado; finalizar move do bloqueado do
 * lojista para o disponivel do entregador; cancelar devolve ao disponivel.
 */
@Entity
@Table(name = "carteiras")
public class Carteira {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Dono da carteira. Chave real a partir daqui: qualquer usuario tem
     * carteira, nao so entregador.
     */
    @Column(nullable = false, unique = true)
    private Long usuarioId;

    /**
     * @deprecated Legado. Substituido por {@link #usuarioId}, que vale para
     * lojista e entregador. Mantido preenchido para nao quebrar as linhas e
     * consultas antigas; nao use em codigo novo.
     */
    @Deprecated
    @Column(unique = true)
    private Long motoboyId;

    // Dinheiro em BigDecimal, nunca em Double: ponto flutuante binario nao
    // representa decimais exatos e o erro acumula a cada soma de saldo.
    // precision/scale casam com o NUMERIC(12,2) das migracoes.
    //
    // O nome da coluna continua "saldo_atual": renomear coluna com dados em
    // producao e troca de nome no Java, nao no banco.
    @Column(name = "saldo_atual", nullable = false, precision = 12, scale = 2)
    private BigDecimal saldoDisponivel = BigDecimal.ZERO;

    /** Reservas de turnos publicados e ainda nao liquidados. Nunca negativo. */
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal saldoBloqueado = BigDecimal.ZERO;

    /**
     * Trava otimista. Obrigatoria em carteira: duas operacoes simultaneas na
     * mesma carteira (liquidar um turno enquanto o dono saca, por exemplo)
     * fariam leitura-modificacao-escrita em cima do mesmo saldo e uma
     * sobrescreveria a outra. Com @Version a segunda falha e pode ser repetida.
     */
    @Version
    private Long versao;

    private String chavePix;

    private LocalDateTime atualizadoEm;

    @PrePersist
    @PreUpdate
    private void preUpdate() {
        atualizadoEm = LocalDateTime.now();
        if (saldoDisponivel == null) saldoDisponivel = BigDecimal.ZERO;
        if (saldoBloqueado == null) saldoBloqueado = BigDecimal.ZERO;
    }

    public Long getId() { return id; }

    public Long getUsuarioId() { return usuarioId; }
    public void setUsuarioId(Long usuarioId) { this.usuarioId = usuarioId; }

    /** @deprecated use {@link #getUsuarioId()}. */
    @Deprecated
    public Long getMotoboyId() { return motoboyId; }

    /** @deprecated use {@link #setUsuarioId(Long)}. */
    @Deprecated
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    /** Nunca devolve null — carteira sem saldo e ZERO, nao ausencia de saldo. */
    public BigDecimal getSaldoDisponivel() {
        return saldoDisponivel == null ? BigDecimal.ZERO : saldoDisponivel;
    }
    public void setSaldoDisponivel(BigDecimal saldoDisponivel) { this.saldoDisponivel = saldoDisponivel; }

    public BigDecimal getSaldoBloqueado() {
        return saldoBloqueado == null ? BigDecimal.ZERO : saldoBloqueado;
    }
    public void setSaldoBloqueado(BigDecimal saldoBloqueado) { this.saldoBloqueado = saldoBloqueado; }

    /** Disponivel + bloqueado: o que o usuario tem na plataforma. */
    public BigDecimal getSaldoTotal() {
        return getSaldoDisponivel().add(getSaldoBloqueado());
    }

    public Long getVersao() { return versao; }

    public String getChavePix() { return chavePix; }
    public void setChavePix(String chavePix) { this.chavePix = chavePix; }

    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
