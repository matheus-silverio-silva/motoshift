package com.motoshift.dto;

import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.Usuario;
import com.motoshift.service.fiscal.DocumentoDaParte;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * A nota como o app a mostra: o documento, as duas partes por extenso e o
 * lado em que quem pediu está.
 *
 * <p>CPF e CNPJ saem mascarados — ver {@link DocumentoDaParte}. Até a V14 o
 * documento inteiro de cada parte ia para a tela e para quem mais recebesse a
 * nota.
 */
public class NotaFiscalResponse {

    private Long id;
    private Long turnoId;
    private Integer numero;
    private String serie;
    private String codigoVerificacao;

    private Long prestadorId;
    private String prestadorNome;
    /** "CPF" ou "CNPJ". */
    private String prestadorDocumentoTipo;
    /** Mascarado; nulo quando o cadastro não tem o documento (ver DocumentoDaParte). */
    private String prestadorDocumento;
    private String prestadorCidade;

    private Long tomadorId;
    private String tomadorNome;
    private String tomadorDocumentoTipo;
    private String tomadorDocumento;
    private String tomadorCidade;

    /** Discriminação do serviço: turno, data, horário e região. */
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

    /**
     * Verdadeiro quando ISS e IRRF saíram do pagamento (há retenção no
     * extrato). Falso: os tributos são o valor aproximado, só informativo, e o
     * líquido é o próprio valor do serviço.
     */
    private boolean tributosRetidos;

    /** O pagamento_recebido documentado e a operação do extrato. */
    private Long transacaoId;
    private UUID operacaoId;

    private LocalDateTime emitidaEm;
    private LocalDateTime canceladaEm;
    private boolean cancelada;
    private String motivoCancelamento;

    /**
     * "prestador" ou "tomador" — quem pediu a nota está de que lado dela.
     * Poupa o app de comparar ids para decidir o texto da tela.
     */
    private String papel;

    public static NotaFiscalResponse from(NotaFiscal n, Usuario prestador, Usuario tomador,
                                          Long solicitanteId) {
        NotaFiscalResponse r = new NotaFiscalResponse();
        r.id = n.getId();
        r.turnoId = n.getTurnoId();
        r.numero = n.getNumero();
        r.serie = n.getSerie();
        r.codigoVerificacao = n.getCodigoVerificacao();

        DocumentoDaParte docPrestador = DocumentoDaParte.de(prestador);
        r.prestadorId = n.getPrestadorId();
        r.prestadorNome = prestador == null ? "Entregador" : prestador.getNome();
        r.prestadorDocumentoTipo = docPrestador.tipo();
        r.prestadorDocumento = docPrestador.numero();
        r.prestadorCidade = cidade(prestador);

        DocumentoDaParte docTomador = DocumentoDaParte.de(tomador);
        r.tomadorId = n.getTomadorId();
        r.tomadorNome = tomador == null ? "Lojista"
                : (tomador.getNomeFantasia() != null && !tomador.getNomeFantasia().isBlank()
                        ? tomador.getNomeFantasia() : tomador.getNome());
        r.tomadorDocumentoTipo = docTomador.tipo();
        r.tomadorDocumento = docTomador.numero();
        r.tomadorCidade = cidade(tomador);

        r.descricaoServico = n.getDescricaoServico();
        r.competencia = n.getCompetencia();
        r.valorServico = n.getValorServico();
        r.issAliquota = n.getIssAliquota();
        r.issValor = n.getIssValor();
        r.irrfAliquota = n.getIrrfAliquota();
        r.irrfValor = n.getIrrfValor();
        r.totalTributos = n.getIssValor().add(n.getIrrfValor());
        r.valorLiquido = n.getValorLiquido();
        r.tributosRetidos = n.isTributosRetidos();
        r.transacaoId = n.getTransacaoId();
        r.operacaoId = n.getOperacaoId();
        r.emitidaEm = n.getEmitidaEm();
        r.canceladaEm = n.getCanceladaEm();
        r.cancelada = n.isCancelada();
        r.motivoCancelamento = n.getMotivoCancelamento();
        r.papel = n.getPrestadorId().equals(solicitanteId) ? "prestador" : "tomador";
        return r;
    }

    private static String cidade(Usuario u) {
        if (u == null || u.getCidade() == null || u.getCidade().isBlank()) return null;
        return u.getEstado() == null || u.getEstado().isBlank()
                ? u.getCidade()
                : u.getCidade() + "/" + u.getEstado();
    }

    public Long getId() { return id; }
    public Long getTurnoId() { return turnoId; }
    public Integer getNumero() { return numero; }
    public String getSerie() { return serie; }
    public String getCodigoVerificacao() { return codigoVerificacao; }
    public Long getPrestadorId() { return prestadorId; }
    public String getPrestadorNome() { return prestadorNome; }
    public String getPrestadorDocumentoTipo() { return prestadorDocumentoTipo; }
    public String getPrestadorDocumento() { return prestadorDocumento; }
    public String getPrestadorCidade() { return prestadorCidade; }
    public Long getTomadorId() { return tomadorId; }
    public String getTomadorNome() { return tomadorNome; }
    public String getTomadorDocumentoTipo() { return tomadorDocumentoTipo; }
    public String getTomadorDocumento() { return tomadorDocumento; }
    public String getTomadorCidade() { return tomadorCidade; }
    public String getDescricaoServico() { return descricaoServico; }
    public LocalDateTime getCompetencia() { return competencia; }
    public BigDecimal getValorServico() { return valorServico; }
    public BigDecimal getIssAliquota() { return issAliquota; }
    public BigDecimal getIssValor() { return issValor; }
    public BigDecimal getIrrfAliquota() { return irrfAliquota; }
    public BigDecimal getIrrfValor() { return irrfValor; }
    public BigDecimal getTotalTributos() { return totalTributos; }
    public BigDecimal getValorLiquido() { return valorLiquido; }
    public boolean isTributosRetidos() { return tributosRetidos; }
    public Long getTransacaoId() { return transacaoId; }
    public UUID getOperacaoId() { return operacaoId; }
    public LocalDateTime getEmitidaEm() { return emitidaEm; }
    public LocalDateTime getCanceladaEm() { return canceladaEm; }
    public boolean isCancelada() { return cancelada; }
    public String getMotivoCancelamento() { return motivoCancelamento; }
    public String getPapel() { return papel; }
}
