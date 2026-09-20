package com.motoshift.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(
    name = "turnos",
    indexes = {
        // Listagem de disponíveis e job de expiração (SCRUM-18 / SCRUM-19).
        @Index(name = "ix_turno_status_inicio", columnList = "status, dataInicio"),
        @Index(name = "ix_turno_status_fim",    columnList = "status, dataFim"),
        // Pré-filtro por bounding box no filtro de raio (SCRUM-18).
        @Index(name = "ix_turno_geo",           columnList = "status, latitude, longitude"),
        @Index(name = "ix_turno_lojista",       columnList = "lojistId"),
        @Index(name = "ix_turno_motoboy",       columnList = "motoboyId")
    }
)
public class Turno {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long lojistId;

    private Long motoboyId;

    @Column(nullable = false)
    private String titulo;

    private String descricao;

    private String regiao;

    @Column(nullable = false)
    private LocalDateTime dataInicio;

    @Column(nullable = false)
    private LocalDateTime dataFim;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valorEstimado;

    // Raio de atuação declarado pelo lojista (quão longe o entregador vai rodar).
    // NÃO é a distância até o motoboy — para isso existem latitude/longitude abaixo.
    private Double raioEntregaKm;

    // ── Geolocalização do ponto de partida (SCRUM-18) ──────────────────────
    // Nullable de propósito: turnos criados antes desta versão não têm
    // coordenada e simplesmente ficam de fora do filtro por raio, sem quebrar
    // as listagens existentes.
    private Double latitude;
    private Double longitude;

    @Column(length = 200)
    private String endereco;

    // Número de vagas de entregador para este turno (lojista pode precisar de vários).
    // Nullable por herança da época do ddl-auto=update, que não conseguia
    // adicionar coluna NOT NULL a uma tabela com linhas. Segue assim porque os
    // turnos anteriores à coluna continuam com NULL no banco, e o getter os lê
    // como 1 — fechar isso agora seria um UPDATE em massa para trocar NULL por
    // um valor que o código já assume.
    private Integer vagas;

    // Valores no banco: aberto | aceito | em_andamento | finalizado | cancelado
    // | expirado. A traducao de e para minusculo e do StatusTurnoConverter.
    @Column(nullable = false)
    private StatusTurno status = StatusTurno.ABERTO;

    // Preenchido pelo job de vencimento quando o turno passa a EXPIRADO (SCRUM-19).
    private LocalDateTime expiradoEm;

    // null (nao finalizado) | pendente | pago
    // PAGO so quando AMBOS confirmaram (lojista pagou + motoboy recebeu)
    private StatusPagamento pagamentoStatus;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    private LocalDateTime atualizadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        atualizadoEm = LocalDateTime.now();
        if (status == null) status = StatusTurno.ABERTO;
        if (vagas == null || vagas < 1) vagas = 1;
    }

    @PreUpdate
    private void preUpdate() {
        atualizadoEm = LocalDateTime.now();
    }

    public Long getId() { return id; }

    public Long getLojistId() { return lojistId; }
    public void setLojistId(Long lojistId) { this.lojistId = lojistId; }

    public Long getMotoboyId() { return motoboyId; }
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    public String getTitulo() { return titulo; }
    public void setTitulo(String titulo) { this.titulo = titulo; }

    public String getDescricao() { return descricao; }
    public void setDescricao(String descricao) { this.descricao = descricao; }

    public String getRegiao() { return regiao; }
    public void setRegiao(String regiao) { this.regiao = regiao; }

    public LocalDateTime getDataInicio() { return dataInicio; }
    public void setDataInicio(LocalDateTime dataInicio) { this.dataInicio = dataInicio; }

    public LocalDateTime getDataFim() { return dataFim; }
    public void setDataFim(LocalDateTime dataFim) { this.dataFim = dataFim; }

    public BigDecimal getValorEstimado() { return valorEstimado; }
    public void setValorEstimado(BigDecimal valorEstimado) { this.valorEstimado = valorEstimado; }

    public Double getRaioEntregaKm() { return raioEntregaKm; }
    public void setRaioEntregaKm(Double raioEntregaKm) { this.raioEntregaKm = raioEntregaKm; }

    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }

    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }

    public String getEndereco() { return endereco; }
    public void setEndereco(String endereco) { this.endereco = endereco; }

    public LocalDateTime getExpiradoEm() { return expiradoEm; }
    public void setExpiradoEm(LocalDateTime expiradoEm) { this.expiradoEm = expiradoEm; }

    public Integer getVagas() { return vagas == null ? 1 : vagas; }
    public void setVagas(Integer vagas) { this.vagas = vagas; }

    public StatusTurno getStatus() { return status; }
    public void setStatus(StatusTurno status) { this.status = status; }

    public StatusPagamento getPagamentoStatus() { return pagamentoStatus; }
    public void setPagamentoStatus(StatusPagamento pagamentoStatus) { this.pagamentoStatus = pagamentoStatus; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
