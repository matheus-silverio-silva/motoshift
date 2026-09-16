package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Nota fiscal de serviço (NFS-e) de um turno concluído.
 *
 * <p><b>Escopo.</b> Este é um documento interno da plataforma, não uma NFS-e
 * transmitida à prefeitura. Não há integração com o padrão ABRASF, certificado
 * digital nem RPS — o objetivo é registrar quem prestou, quem tomou, quanto
 * custou o serviço e quanto disso é imposto, com a numeração e o código de
 * verificação que um documento desses tem. Trocar isto por uma emissão real é
 * substituir {@link com.motoshift.service.NotaFiscalService} por um cliente do
 * provedor municipal; o modelo de dados abaixo já é o que ele precisaria.
 *
 * <p><b>Quem é quem.</b> Em uma entrega agendada o serviço é prestado pelo
 * entregador e tomado pelo lojista — sempre nessa direção, mesmo quando é o
 * lojista quem clica em "emitir". Por isso {@link #emitidaPorId} é separado de
 * {@link #prestadorId}: os dois lados podem disparar a emissão, mas o
 * documento tem um prestador só.
 *
 * <p>Uma nota por par (turno, prestador): um turno com três vagas gera três
 * notas, uma para cada entregador.
 */
@Entity
@Table(
    name = "notas_fiscais",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_nota_turno_prestador",
        columnNames = {"turnoId", "prestadorId"}
    ),
    indexes = {
        @Index(name = "ix_nota_prestador", columnList = "prestadorId, emitidaEm"),
        @Index(name = "ix_nota_tomador",   columnList = "tomadorId, emitidaEm"),
        @Index(name = "ix_nota_turno",     columnList = "turnoId")
    }
)
public class NotaFiscal {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long turnoId;

    /** Quem prestou o serviço: o entregador. */
    @Column(nullable = false)
    private Long prestadorId;

    /** Quem tomou o serviço: o lojista dono do turno. */
    @Column(nullable = false)
    private Long tomadorId;

    /** Quem disparou a emissão — pode ser qualquer um dos dois lados. */
    @Column(nullable = false)
    private Long emitidaPorId;

    /** Sequencial por prestador, como numeração de talão. */
    @Column(nullable = false)
    private Integer numero;

    @Column(nullable = false, length = 8)
    private String serie;

    /**
     * Código de verificação do documento. Em uma NFS-e real é o que permite
     * conferir a nota no site da prefeitura; aqui é derivado dos dados da
     * própria nota, de forma estável.
     */
    @Column(nullable = false, length = 16)
    private String codigoVerificacao;

    @Column(nullable = false, length = 300)
    private String descricaoServico;

    /** Base de cálculo: o valor do turno. */
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valorServico;

    // ── Tributos ────────────────────────────────────────────────────────────
    // Dois, de propósito: ISS (municipal, sobre o serviço) e IRRF (retenção na
    // fonte). Bastam para mostrar base de cálculo, alíquota, valor retido e
    // valor líquido — que é a estrutura de qualquer nota. Acrescentar PIS,
    // COFINS e CSLL seria repetir a mesma conta com outros nomes.

    @Column(nullable = false, precision = 6, scale = 4)
    private BigDecimal issAliquota;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal issValor;

    @Column(nullable = false, precision = 6, scale = 4)
    private BigDecimal irrfAliquota;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal irrfValor;

    /** Valor do serviço menos as retenções. */
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valorLiquido;

    @Column(nullable = false, updatable = false)
    private LocalDateTime emitidaEm;

    /** Preenchido quando a nota é cancelada; nulo enquanto ela vale. */
    private LocalDateTime canceladaEm;

    private String motivoCancelamento;

    @PrePersist
    private void prePersist() {
        if (emitidaEm == null) emitidaEm = LocalDateTime.now();
    }

    public boolean isCancelada() {
        return canceladaEm != null;
    }

    public Long getId() { return id; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public Long getPrestadorId() { return prestadorId; }
    public void setPrestadorId(Long prestadorId) { this.prestadorId = prestadorId; }

    public Long getTomadorId() { return tomadorId; }
    public void setTomadorId(Long tomadorId) { this.tomadorId = tomadorId; }

    public Long getEmitidaPorId() { return emitidaPorId; }
    public void setEmitidaPorId(Long emitidaPorId) { this.emitidaPorId = emitidaPorId; }

    public Integer getNumero() { return numero; }
    public void setNumero(Integer numero) { this.numero = numero; }

    public String getSerie() { return serie; }
    public void setSerie(String serie) { this.serie = serie; }

    public String getCodigoVerificacao() { return codigoVerificacao; }
    public void setCodigoVerificacao(String c) { this.codigoVerificacao = c; }

    public String getDescricaoServico() { return descricaoServico; }
    public void setDescricaoServico(String d) { this.descricaoServico = d; }

    public BigDecimal getValorServico() { return valorServico; }
    public void setValorServico(BigDecimal v) { this.valorServico = v; }

    public BigDecimal getIssAliquota() { return issAliquota; }
    public void setIssAliquota(BigDecimal v) { this.issAliquota = v; }

    public BigDecimal getIssValor() { return issValor; }
    public void setIssValor(BigDecimal v) { this.issValor = v; }

    public BigDecimal getIrrfAliquota() { return irrfAliquota; }
    public void setIrrfAliquota(BigDecimal v) { this.irrfAliquota = v; }

    public BigDecimal getIrrfValor() { return irrfValor; }
    public void setIrrfValor(BigDecimal v) { this.irrfValor = v; }

    public BigDecimal getValorLiquido() { return valorLiquido; }
    public void setValorLiquido(BigDecimal v) { this.valorLiquido = v; }

    public LocalDateTime getEmitidaEm() { return emitidaEm; }
    public void setEmitidaEm(LocalDateTime t) { this.emitidaEm = t; }

    public LocalDateTime getCanceladaEm() { return canceladaEm; }
    public void setCanceladaEm(LocalDateTime t) { this.canceladaEm = t; }

    public String getMotivoCancelamento() { return motivoCancelamento; }
    public void setMotivoCancelamento(String m) { this.motivoCancelamento = m; }
}
