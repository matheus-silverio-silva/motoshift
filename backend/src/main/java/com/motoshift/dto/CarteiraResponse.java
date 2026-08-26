package com.motoshift.dto;

import com.motoshift.entity.Carteira;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.List;

public class CarteiraResponse {

    private Long id;
    private Long motoboyId;
    private BigDecimal saldoAtual;
    private BigDecimal ganhosMensais;
    private LocalDateTime atualizadoEm;
    private List<TransacaoResponse> transacoes;

    public static CarteiraResponse from(Carteira c) {
        CarteiraResponse r = new CarteiraResponse();
        r.id = c.getId();
        r.motoboyId = c.getMotoboyId();
        r.saldoAtual = emReais(c.getSaldoAtual());
        r.ganhosMensais = emReais(c.getGanhosMensais());
        r.atualizadoEm = c.getAtualizadoEm();
        return r;
    }

    public Long getId() { return id; }
    public Long getMotoboyId() { return motoboyId; }
    public BigDecimal getSaldoAtual() { return saldoAtual; }
    public BigDecimal getGanhosMensais() { return ganhosMensais; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
    public List<TransacaoResponse> getTransacoes() { return transacoes; }
    public void setTransacoes(List<TransacaoResponse> transacoes) { this.transacoes = transacoes; }

    /** Borda de saida: o app recebe sempre 2 casas decimais. */
    static BigDecimal emReais(BigDecimal v) {
        return v == null ? null : v.setScale(2, RoundingMode.HALF_UP);
    }
}
