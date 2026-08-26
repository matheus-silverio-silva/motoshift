package com.motoshift.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.time.LocalDateTime;

public class TurnoRequest {

    @NotNull
    private Long lojistId;

    @NotNull
    private String titulo;

    private String descricao;
    private String regiao;

    @NotNull
    private LocalDateTime dataInicio;

    @NotNull
    private LocalDateTime dataFim;

    @NotNull
    @Positive
    private Double valorEstimado;

    private Double raioEntregaKm;

    // Ponto de partida do turno (SCRUM-18). Opcional: sem coordenada o turno
    // continua sendo criado, só não aparece no filtro por raio.
    private Double latitude;
    private Double longitude;
    private String endereco;

    // Número de vagas de entregador (opcional; default 1 no serviço).
    private Integer vagas;

    public Long getLojistId() { return lojistId; }
    public void setLojistId(Long lojistId) { this.lojistId = lojistId; }

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

    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }

    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }

    public String getEndereco() { return endereco; }
    public void setEndereco(String endereco) { this.endereco = endereco; }

    public Integer getVagas() { return vagas; }
    public void setVagas(Integer vagas) { this.vagas = vagas; }
}
