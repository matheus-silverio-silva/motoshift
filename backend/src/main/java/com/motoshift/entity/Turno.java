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
    // IMPORTANTE: coluna nullable de propósito. Com ddl-auto=update, o banco não
    // consegue adicionar uma coluna NOT NULL a uma tabela que já tem linhas — isso
    // quebraria as consultas de turno em produção. Sendo nullable, a migração
    // ocorre sem erro; linhas antigas ficam NULL e o getter devolve 1 (default).
    private Integer vagas;

    // aberto | aceito | em_andamento | finalizado | cancelado | expirado
    @Column(nullable = false)
    private String status = "aberto";

    // Preenchido pelo job de vencimento quando o turno passa a "expirado" (SCRUM-19).
    private LocalDateTime expiradoEm;

    // null (não finalizado) | pendente | pago
    // "pago" só quando AMBOS confirmaram (lojista pagou + motoboy recebeu)
    private String pagamentoStatus;

    // Dupla confirmação de pagamento
    private LocalDateTime lojistaConfirmouEm;
    private LocalDateTime motoboyConfirmouEm;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    private LocalDateTime atualizadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        atualizadoEm = LocalDateTime.now();
        if (status == null) status = "aberto";
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

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getPagamentoStatus() { return pagamentoStatus; }
    public void setPagamentoStatus(String pagamentoStatus) { this.pagamentoStatus = pagamentoStatus; }

    public LocalDateTime getLojistaConfirmouEm() { return lojistaConfirmouEm; }
    public void setLojistaConfirmouEm(LocalDateTime t) { this.lojistaConfirmouEm = t; }

    public LocalDateTime getMotoboyConfirmouEm() { return motoboyConfirmouEm; }
    public void setMotoboyConfirmouEm(LocalDateTime t) { this.motoboyConfirmouEm = t; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
