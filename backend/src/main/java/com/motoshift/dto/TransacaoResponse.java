package com.motoshift.dto;

import com.motoshift.entity.Transacao;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public class TransacaoResponse {

    private Long id;
    private Long usuarioId;
    private Long contraparteId;
    private Long turnoId;
    private String tipo;
    private BigDecimal valor;
    private String descricao;
    private String status;
    private LocalDateTime criadoEm;

    /**
     * @deprecated Espelha usuarioId. Mantido para o app antigo, que le este
     * campo como `int` NAO-NULAVEL (transacao.dart) — e uma transacao com
     * motoboy_id nulo no meio do extrato quebraria a tela de carteira inteira,
     * de forma permanente para aquele usuario.
     */
    @Deprecated
    private Long motoboyId;

    @SuppressWarnings("deprecation")
    public static TransacaoResponse from(Transacao t) {
        TransacaoResponse r = new TransacaoResponse();
        r.id = t.getId();
        r.usuarioId = t.getUsuarioId();
        r.contraparteId = t.getContraparteId();
        r.motoboyId = t.getUsuarioId();
        r.turnoId = t.getTurnoId();
        r.tipo = t.getTipo();
        r.valor = CarteiraResponse.emReais(t.getValor());
        r.descricao = t.getDescricao();
        r.status = t.getStatus();
        r.criadoEm = t.getCriadoEm();
        return r;
    }

    public Long getId() { return id; }
    public Long getUsuarioId() { return usuarioId; }
    public Long getContraparteId() { return contraparteId; }
    public Long getTurnoId() { return turnoId; }
    public String getTipo() { return tipo; }
    public BigDecimal getValor() { return valor; }
    public String getDescricao() { return descricao; }
    public String getStatus() { return status; }
    public LocalDateTime getCriadoEm() { return criadoEm; }

    /** @deprecated use {@link #getUsuarioId()}. */
    @Deprecated
    public Long getMotoboyId() { return motoboyId; }
}
