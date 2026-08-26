package com.motoshift.dto;

import com.motoshift.entity.Carteira;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.List;

public class CarteiraResponse {

    private Long id;
    private Long usuarioId;
    private BigDecimal saldoDisponivel;
    private BigDecimal saldoBloqueado;
    private BigDecimal saldoTotal;

    /**
     * @deprecated Espelha saldoDisponivel. Mantido porque o app em producao le
     * este campo como obrigatorio — remover agora quebraria o parse no cliente
     * antigo. Sai quando o app tiver migrado para saldoDisponivel.
     */
    @Deprecated
    private BigDecimal saldoAtual;

    /** @deprecated idem saldoAtual — o app le como obrigatorio. */
    @Deprecated
    private Long motoboyId;

    /**
     * Ganhos do mes corrente. NAO vem mais de um contador na carteira: aquele
     * campo so incrementava e nunca era resetado, entao mostrava o acumulado de
     * sempre com nome de "mensal". Agora e somado das transacoes do mes.
     * Preenchido pelo service, que tem acesso ao repositorio.
     */
    private BigDecimal ganhosMensais;

    private LocalDateTime atualizadoEm;
    private List<TransacaoResponse> transacoes;

    @SuppressWarnings("deprecation")
    public static CarteiraResponse from(Carteira c) {
        CarteiraResponse r = new CarteiraResponse();
        r.id = c.getId();
        r.usuarioId = c.getUsuarioId();
        r.motoboyId = c.getMotoboyId();
        r.saldoDisponivel = emReais(c.getSaldoDisponivel());
        r.saldoBloqueado = emReais(c.getSaldoBloqueado());
        r.saldoTotal = emReais(c.getSaldoTotal());
        r.saldoAtual = r.saldoDisponivel;
        r.atualizadoEm = c.getAtualizadoEm();
        return r;
    }

    public Long getId() { return id; }
    public Long getUsuarioId() { return usuarioId; }
    public BigDecimal getSaldoDisponivel() { return saldoDisponivel; }
    public BigDecimal getSaldoBloqueado() { return saldoBloqueado; }
    public BigDecimal getSaldoTotal() { return saldoTotal; }

    /** @deprecated use {@link #getSaldoDisponivel()}. */
    @Deprecated
    public BigDecimal getSaldoAtual() { return saldoAtual; }

    /** @deprecated use {@link #getUsuarioId()}. */
    @Deprecated
    public Long getMotoboyId() { return motoboyId; }

    public BigDecimal getGanhosMensais() { return ganhosMensais; }
    public void setGanhosMensais(BigDecimal ganhosMensais) { this.ganhosMensais = emReais(ganhosMensais); }

    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
    public List<TransacaoResponse> getTransacoes() { return transacoes; }
    public void setTransacoes(List<TransacaoResponse> transacoes) { this.transacoes = transacoes; }

    /** Borda de saida: o app recebe sempre 2 casas decimais. */
    static BigDecimal emReais(BigDecimal v) {
        return v == null ? null : v.setScale(2, RoundingMode.HALF_UP);
    }
}
