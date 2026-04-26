package com.motoshift.dto;

import com.motoshift.entity.Turno;

import java.time.LocalDateTime;

public class TurnoResponse {

    private Long id;
    private Long lojistId;
    private Long motoboyId;
    private String titulo;
    private String descricao;
    private String regiao;
    private LocalDateTime dataInicio;
    private LocalDateTime dataFim;
    private Double valorEstimado;
    private Double raioEntregaKm;
    private String status;
    private LocalDateTime criadoEm;
    private LocalDateTime atualizadoEm;

    public static TurnoResponse from(Turno t) {
        TurnoResponse r = new TurnoResponse();
        r.id = t.getId();
        r.lojistId = t.getLojistId();
        r.motoboyId = t.getMotoboyId();
        r.titulo = t.getTitulo();
        r.descricao = t.getDescricao();
        r.regiao = t.getRegiao();
        r.dataInicio = t.getDataInicio();
        r.dataFim = t.getDataFim();
        r.valorEstimado = t.getValorEstimado();
        r.raioEntregaKm = t.getRaioEntregaKm();
        r.status = t.getStatus();
        r.criadoEm = t.getCriadoEm();
        r.atualizadoEm = t.getAtualizadoEm();
        return r;
    }

    public Long getId() { return id; }
    public Long getLojistId() { return lojistId; }
    public Long getMotoboyId() { return motoboyId; }
    public String getTitulo() { return titulo; }
    public String getDescricao() { return descricao; }
    public String getRegiao() { return regiao; }
    public LocalDateTime getDataInicio() { return dataInicio; }
    public LocalDateTime getDataFim() { return dataFim; }
    public Double getValorEstimado() { return valorEstimado; }
    public Double getRaioEntregaKm() { return raioEntregaKm; }
    public String getStatus() { return status; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
