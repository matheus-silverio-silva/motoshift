package com.motoshift.dto;

import com.motoshift.entity.Transacao;

import java.time.LocalDateTime;

public class TransacaoResponse {

    private Long id;
    private Long motoboyId;
    private Long turnoId;
    private String tipo;
    private Double valor;
    private String descricao;
    private String status;
    private LocalDateTime criadoEm;

    public static TransacaoResponse from(Transacao t) {
        TransacaoResponse r = new TransacaoResponse();
        r.id = t.getId();
        r.motoboyId = t.getMotoboyId();
        r.turnoId = t.getTurnoId();
        r.tipo = t.getTipo();
        r.valor = t.getValor();
        r.descricao = t.getDescricao();
        r.status = t.getStatus();
        r.criadoEm = t.getCriadoEm();
        return r;
    }

    public Long getId() { return id; }
    public Long getMotoboyId() { return motoboyId; }
    public Long getTurnoId() { return turnoId; }
    public String getTipo() { return tipo; }
    public Double getValor() { return valor; }
    public String getDescricao() { return descricao; }
    public String getStatus() { return status; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
}
