package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "carteiras")
public class Carteira {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private Long motoboyId;

    // Dinheiro em BigDecimal, nunca em Double: ponto flutuante binario nao
    // representa decimais exatos e o erro acumula a cada soma de saldo.
    // precision/scale casam com o NUMERIC(12,2) da migracao V3 — sem eles o
    // Hibernate assumiria numeric(38,2) e o ddl-auto=validate reprovaria.
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal saldoAtual = BigDecimal.ZERO;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal ganhosMensais = BigDecimal.ZERO;

    private String chavePix;

    private LocalDateTime atualizadoEm;

    @PrePersist
    @PreUpdate
    private void preUpdate() {
        atualizadoEm = LocalDateTime.now();
        if (saldoAtual == null) saldoAtual = BigDecimal.ZERO;
        if (ganhosMensais == null) ganhosMensais = BigDecimal.ZERO;
    }

    public Long getId() { return id; }

    public Long getMotoboyId() { return motoboyId; }
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    /** Nunca devolve null — carteira sem saldo e ZERO, nao ausencia de saldo. */
    public BigDecimal getSaldoAtual() { return saldoAtual == null ? BigDecimal.ZERO : saldoAtual; }
    public void setSaldoAtual(BigDecimal saldoAtual) { this.saldoAtual = saldoAtual; }

    public BigDecimal getGanhosMensais() { return ganhosMensais == null ? BigDecimal.ZERO : ganhosMensais; }
    public void setGanhosMensais(BigDecimal ganhosMensais) { this.ganhosMensais = ganhosMensais; }

    public String getChavePix() { return chavePix; }
    public void setChavePix(String chavePix) { this.chavePix = chavePix; }

    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
