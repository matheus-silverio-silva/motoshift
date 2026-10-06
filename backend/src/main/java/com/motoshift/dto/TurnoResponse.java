package com.motoshift.dto;

import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
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
    // A loja deste turno tem o entregador que pediu a lista entre os
    // favoritos (V18) — o selo "Loja que já te chamou". Só na lista de
    // disponíveis; nas outras respostas fica false.
    private boolean lojaQueJaTeChamou;
    private LocalDateTime expiradoEm;
    private Integer vagas;
    private Integer vagasPreenchidas;
    // Alguem ja fez check-in neste turno. Com o inicio (dataInicio), e o que o
    // app precisa para saber se "Finalizar" seria aceito: o backend recusa
    // (409) o turno que nao comecou ou em que ninguem chegou.
    private boolean algumCheckin;
    // Tipados como enum: o JSON continua saindo minúsculo por causa do
    // @JsonValue em StatusTurno/StatusPagamento, e o contrato com o app fica
    // preso ao enum em vez de a uma String que qualquer atribuição altera.
    private StatusTurno status;
    private StatusPagamento pagamentoStatus;
    // lojistaConfirmouEm e motoboyConfirmouEm saíram daqui.
    //
    // A V6 já as tinha removido do Turno e elas sobreviviam no JSON, sempre
    // nulas, para não quebrar um app que as lia. Agora a dupla confirmação
    // inteira acabou — a liquidação é automática — e manter duas chaves nulas
    // só documentaria um fluxo que não existe mais. Este era o "deploy só dela"
    // que o comentário anterior previa.
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
    public boolean isLojaQueJaTeChamou() { return lojaQueJaTeChamou; }
    public void setLojaQueJaTeChamou(boolean v) { this.lojaQueJaTeChamou = v; }
    public LocalDateTime getExpiradoEm() { return expiradoEm; }
    public Integer getVagas() { return vagas; }
    public Integer getVagasPreenchidas() { return vagasPreenchidas; }
    public void setVagasPreenchidas(Integer v) { this.vagasPreenchidas = v; }
    public boolean isAlgumCheckin() { return algumCheckin; }
    public void setAlgumCheckin(boolean v) { this.algumCheckin = v; }
    public StatusTurno getStatus() { return status; }
    public StatusPagamento getPagamentoStatus() { return pagamentoStatus; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
