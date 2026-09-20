package com.motoshift.dto;

import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Os filtros do extrato, como chegam na query string.
 *
 * <p>O Spring monta este objeto a partir dos parâmetros da requisição, então
 * cada campo aqui é um parâmetro da API. O filtro saiu do cliente e veio para
 * cá: antes o app baixava o extrato inteiro e escondia linhas na tela, o que
 * funcionava com vinte lançamentos e não funciona com dois mil.
 *
 * <p><b>Datas chegam como dia, não como instante.</b> Quem filtra pensa em
 * "01/09 a 30/09", e o fim do intervalo precisa incluir o dia 30 inteiro. A
 * conversão está em {@link #getDataFim()}, num lugar só, em vez de espalhada
 * por cada consulta que usa o filtro.
 */
public class ExtratoFiltro {

    private LocalDate dataInicio;
    private LocalDate dataFim;
    private List<TipoTransacao> tipos;
    private StatusTransacao status;
    private NaturezaTransacao natureza;
    private Long turnoId;
    private Long contraparteId;
    private BigDecimal valorMin;
    private BigDecimal valorMax;
    private String busca;

    public LocalDateTime getDataInicio() {
        return dataInicio == null ? null : dataInicio.atStartOfDay();
    }

    /** Começo do dia SEGUINTE: a consulta usa {@code <}, então o dia final entra inteiro. */
    public LocalDateTime getDataFim() {
        return dataFim == null ? null : dataFim.plusDays(1).atStartOfDay();
    }

    public LocalDate getDataInicioBruta() { return dataInicio; }
    public LocalDate getDataFimBruta() { return dataFim; }

    public void setDataInicio(LocalDate dataInicio) { this.dataInicio = dataInicio; }
    public void setDataFim(LocalDate dataFim) { this.dataFim = dataFim; }

    public List<TipoTransacao> getTipos() { return tipos; }
    public void setTipos(List<TipoTransacao> tipos) { this.tipos = tipos; }

    public StatusTransacao getStatus() { return status; }
    public void setStatus(StatusTransacao status) { this.status = status; }

    public NaturezaTransacao getNatureza() { return natureza; }
    public void setNatureza(NaturezaTransacao natureza) { this.natureza = natureza; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public Long getContraparteId() { return contraparteId; }
    public void setContraparteId(Long contraparteId) { this.contraparteId = contraparteId; }

    public BigDecimal getValorMin() { return valorMin; }
    public void setValorMin(BigDecimal valorMin) { this.valorMin = valorMin; }

    public BigDecimal getValorMax() { return valorMax; }
    public void setValorMax(BigDecimal valorMax) { this.valorMax = valorMax; }

    public String getBusca() { return busca; }
    public void setBusca(String busca) { this.busca = busca; }
}
