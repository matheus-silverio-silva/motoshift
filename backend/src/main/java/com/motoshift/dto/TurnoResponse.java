package com.motoshift.dto;

import com.motoshift.entity.Turno;

import java.math.BigDecimal;
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
    private BigDecimal valorEstimado;
    private Double raioEntregaKm;
    private Double latitude;
    private Double longitude;
    private String endereco;
    // Distância do usuário até o turno, em km. Só vem preenchida quando a
    // requisição informou lat/lng; null caso contrário.
    private Double distanciaKm;
    private LocalDateTime expiradoEm;
    private Integer vagas;
    private Integer vagasPreenchidas;
    private String status;
    private String pagamentoStatus;
    private LocalDateTime lojistaConfirmouEm;
    private LocalDateTime motoboyConfirmouEm;
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
        r.valorEstimado = CarteiraResponse.emReais(t.getValorEstimado());
        r.raioEntregaKm = t.getRaioEntregaKm();
        r.latitude = t.getLatitude();
        r.longitude = t.getLongitude();
        r.endereco = t.getEndereco();
        r.expiradoEm = t.getExpiradoEm();
        r.vagas = t.getVagas();
        r.vagasPreenchidas = 0; // atualizado pelo serviço via setVagasPreenchidas
        r.status = t.getStatus();
        r.pagamentoStatus = t.getPagamentoStatus();
        r.lojistaConfirmouEm = t.getLojistaConfirmouEm();
        r.motoboyConfirmouEm = t.getMotoboyConfirmouEm();
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
    public BigDecimal getValorEstimado() { return valorEstimado; }
    public Double getRaioEntregaKm() { return raioEntregaKm; }
    public Double getLatitude() { return latitude; }
    public Double getLongitude() { return longitude; }
    public String getEndereco() { return endereco; }
    public Double getDistanciaKm() { return distanciaKm; }
    public void setDistanciaKm(Double d) { this.distanciaKm = d; }
    public LocalDateTime getExpiradoEm() { return expiradoEm; }
    public Integer getVagas() { return vagas; }
    public Integer getVagasPreenchidas() { return vagasPreenchidas; }
    public void setVagasPreenchidas(Integer v) { this.vagasPreenchidas = v; }
    public String getStatus() { return status; }
    public String getPagamentoStatus() { return pagamentoStatus; }
    public LocalDateTime getLojistaConfirmouEm() { return lojistaConfirmouEm; }
    public LocalDateTime getMotoboyConfirmouEm() { return motoboyConfirmouEm; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
