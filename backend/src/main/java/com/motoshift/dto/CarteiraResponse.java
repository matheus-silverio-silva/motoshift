package com.motoshift.dto;

import com.motoshift.entity.Carteira;

import java.time.LocalDateTime;
import java.util.List;

public class CarteiraResponse {

    private Long id;
    private Long motoboyId;
    private Double saldoAtual;
    private Double ganhosMensais;
    private LocalDateTime atualizadoEm;
    private List<TransacaoResponse> transacoes;

    public static CarteiraResponse from(Carteira c) {
        CarteiraResponse r = new CarteiraResponse();
        r.id = c.getId();
        r.motoboyId = c.getMotoboyId();
        r.saldoAtual = c.getSaldoAtual();
        r.ganhosMensais = c.getGanhosMensais();
        r.atualizadoEm = c.getAtualizadoEm();
        return r;
    }

    public Long getId() { return id; }
    public Long getMotoboyId() { return motoboyId; }
    public Double getSaldoAtual() { return saldoAtual; }
    public Double getGanhosMensais() { return ganhosMensais; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
    public List<TransacaoResponse> getTransacoes() { return transacoes; }
    public void setTransacoes(List<TransacaoResponse> transacoes) { this.transacoes = transacoes; }
}
