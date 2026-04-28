package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "carteiras")
public class Carteira {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private Long motoboyId;

    @Column(nullable = false)
    private Double saldoAtual = 0.0;

    @Column(nullable = false)
    private Double ganhosMensais = 0.0;

    private String chavePix;

    private LocalDateTime atualizadoEm;

    @PrePersist
    @PreUpdate
    private void preUpdate() {
        atualizadoEm = LocalDateTime.now();
        if (saldoAtual == null) saldoAtual = 0.0;
        if (ganhosMensais == null) ganhosMensais = 0.0;
    }

    public Long getId() { return id; }

    public Long getMotoboyId() { return motoboyId; }
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    public Double getSaldoAtual() { return saldoAtual; }
    public void setSaldoAtual(Double saldoAtual) { this.saldoAtual = saldoAtual; }

    public Double getGanhosMensais() { return ganhosMensais; }
    public void setGanhosMensais(Double ganhosMensais) { this.ganhosMensais = ganhosMensais; }

    public String getChavePix() { return chavePix; }
    public void setChavePix(String chavePix) { this.chavePix = chavePix; }

    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
