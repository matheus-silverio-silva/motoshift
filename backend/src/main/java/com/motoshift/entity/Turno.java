package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "turnos")
public class Turno {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long lojistId;

    private Long motoboyId;

    @Column(nullable = false)
    private String titulo;

    private String descricao;

    private String regiao;

    @Column(nullable = false)
    private LocalDateTime dataInicio;

    @Column(nullable = false)
    private LocalDateTime dataFim;

    @Column(nullable = false)
    private Double valorEstimado;

    private Double raioEntregaKm;

    // aberto | aceito | em_andamento | finalizado | cancelado
    @Column(nullable = false)
    private String status = "aberto";

    // null (não finalizado) | pendente | pago
    // "pago" só quando AMBOS confirmaram (lojista pagou + motoboy recebeu)
    private String pagamentoStatus;

    // Dupla confirmação de pagamento
    private LocalDateTime lojistaConfirmouEm;
    private LocalDateTime motoboyConfirmouEm;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    private LocalDateTime atualizadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        atualizadoEm = LocalDateTime.now();
        if (status == null) status = "aberto";
    }

    @PreUpdate
    private void preUpdate() {
        atualizadoEm = LocalDateTime.now();
    }

    public Long getId() { return id; }

    public Long getLojistId() { return lojistId; }
    public void setLojistId(Long lojistId) { this.lojistId = lojistId; }

    public Long getMotoboyId() { return motoboyId; }
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    public String getTitulo() { return titulo; }
    public void setTitulo(String titulo) { this.titulo = titulo; }

    public String getDescricao() { return descricao; }
    public void setDescricao(String descricao) { this.descricao = descricao; }

    public String getRegiao() { return regiao; }
    public void setRegiao(String regiao) { this.regiao = regiao; }

    public LocalDateTime getDataInicio() { return dataInicio; }
    public void setDataInicio(LocalDateTime dataInicio) { this.dataInicio = dataInicio; }

    public LocalDateTime getDataFim() { return dataFim; }
    public void setDataFim(LocalDateTime dataFim) { this.dataFim = dataFim; }

    public Double getValorEstimado() { return valorEstimado; }
    public void setValorEstimado(Double valorEstimado) { this.valorEstimado = valorEstimado; }

    public Double getRaioEntregaKm() { return raioEntregaKm; }
    public void setRaioEntregaKm(Double raioEntregaKm) { this.raioEntregaKm = raioEntregaKm; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getPagamentoStatus() { return pagamentoStatus; }
    public void setPagamentoStatus(String pagamentoStatus) { this.pagamentoStatus = pagamentoStatus; }

    public LocalDateTime getLojistaConfirmouEm() { return lojistaConfirmouEm; }
    public void setLojistaConfirmouEm(LocalDateTime t) { this.lojistaConfirmouEm = t; }

    public LocalDateTime getMotoboyConfirmouEm() { return motoboyConfirmouEm; }
    public void setMotoboyConfirmouEm(LocalDateTime t) { this.motoboyConfirmouEm = t; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
