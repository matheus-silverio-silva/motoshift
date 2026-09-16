package com.motoshift.dto;

import com.motoshift.entity.NotaFiscal;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * A nota como o app a mostra: o documento, as duas partes por extenso e o
 * lado em que quem pediu está.
 */
public class NotaFiscalResponse {

    private Long id;
    private Long turnoId;
    private Integer numero;
    private String serie;
    private String codigoVerificacao;

    private Long prestadorId;
    private String prestadorNome;
    private String prestadorDocumento;

    private Long tomadorId;
    private String tomadorNome;
    private String tomadorDocumento;

    private String descricaoServico;

    /** Data do serviço — o início do turno, não a data da emissão. */
    private LocalDateTime competencia;

    private BigDecimal valorServico;
    private BigDecimal issAliquota;
    private BigDecimal issValor;
    private BigDecimal irrfAliquota;
    private BigDecimal irrfValor;
    private BigDecimal totalTributos;
    private BigDecimal valorLiquido;

    private LocalDateTime emitidaEm;
    private LocalDateTime canceladaEm;
    private boolean cancelada;
    private String motivoCancelamento;

    /**
     * "prestador" ou "tomador" — quem pediu a nota está de que lado dela.
     * Poupa o app de comparar ids para decidir o texto da tela.
     */
    private String papel;

    public static NotaFiscalResponse from(NotaFiscal n,
                                          String prestadorNome,
                                          String prestadorDocumento,
                                          String tomadorNome,
                                          String tomadorDocumento,
                                          LocalDateTime competencia,
                                          Long solicitanteId) {
        NotaFiscalResponse r = new NotaFiscalResponse();
        r.id = n.getId();
        r.turnoId = n.getTurnoId();
        r.numero = n.getNumero();
        r.serie = n.getSerie();
        r.codigoVerificacao = n.getCodigoVerificacao();
        r.prestadorId = n.getPrestadorId();
        r.prestadorNome = prestadorNome;
        r.prestadorDocumento = prestadorDocumento;
        r.tomadorId = n.getTomadorId();
        r.tomadorNome = tomadorNome;
        r.tomadorDocumento = tomadorDocumento;
        r.descricaoServico = n.getDescricaoServico();
        r.competencia = competencia;
        r.valorServico = n.getValorServico();
        r.issAliquota = n.getIssAliquota();
        r.issValor = n.getIssValor();
        r.irrfAliquota = n.getIrrfAliquota();
        r.irrfValor = n.getIrrfValor();
        r.totalTributos = n.getIssValor().add(n.getIrrfValor());
        r.valorLiquido = n.getValorLiquido();
        r.emitidaEm = n.getEmitidaEm();
        r.canceladaEm = n.getCanceladaEm();
        r.cancelada = n.isCancelada();
        r.motivoCancelamento = n.getMotivoCancelamento();
        r.papel = n.getPrestadorId().equals(solicitanteId) ? "prestador" : "tomador";
        return r;
    }

    public Long getId() { return id; }
    public Long getTurnoId() { return turnoId; }
    public Integer getNumero() { return numero; }
    public String getSerie() { return serie; }
    public String getCodigoVerificacao() { return codigoVerificacao; }
    public Long getPrestadorId() { return prestadorId; }
    public String getPrestadorNome() { return prestadorNome; }
    public String getPrestadorDocumento() { return prestadorDocumento; }
    public Long getTomadorId() { return tomadorId; }
    public String getTomadorNome() { return tomadorNome; }
    public String getTomadorDocumento() { return tomadorDocumento; }
    public String getDescricaoServico() { return descricaoServico; }
    public LocalDateTime getCompetencia() { return competencia; }
    public BigDecimal getValorServico() { return valorServico; }
    public BigDecimal getIssAliquota() { return issAliquota; }
    public BigDecimal getIssValor() { return issValor; }
    public BigDecimal getIrrfAliquota() { return irrfAliquota; }
    public BigDecimal getIrrfValor() { return irrfValor; }
    public BigDecimal getTotalTributos() { return totalTributos; }
    public BigDecimal getValorLiquido() { return valorLiquido; }
    public LocalDateTime getEmitidaEm() { return emitidaEm; }
    public LocalDateTime getCanceladaEm() { return canceladaEm; }
    public boolean isCancelada() { return cancelada; }
    public String getMotivoCancelamento() { return motivoCancelamento; }
    public String getPapel() { return papel; }
}
