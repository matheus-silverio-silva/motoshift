package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Notificação in-app de um usuário (SCRUM-20).
 *
 * Cobre vencimento, cancelamento, demora na troca de status e pagamento.
 * O par ({@code tipo}, {@code referenciaId}) serve para deduplicação: um job
 * que roda a cada 5 minutos não pode gerar a mesma notificação 12 vezes por hora.
 */
@Entity
@Table(
    name = "notificacoes",
    indexes = {
        // Listagem do sino: "minhas notificações, não lidas primeiro".
        @Index(name = "ix_notificacao_usuario", columnList = "usuarioId, lida, criadoEm"),
        // Deduplicação nos jobs agendados.
        @Index(name = "ix_notificacao_dedup",   columnList = "usuarioId, tipo, referenciaId")
    }
)
public class Notificacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long usuarioId;

    // turno_expirado | turno_vencendo | turno_aceito | turno_lotado
    // | turno_cancelado | turno_pendente_finalizacao | pagamento_pendente
    // | pagamento_confirmado | avaliacao_pendente
    @Column(nullable = false, length = 40)
    private String tipo;

    @Column(nullable = false, length = 120)
    private String titulo;

    @Column(nullable = false, length = 255)
    private String mensagem;

    // Deep link no app: "turno" | "avaliacao" | "carteira"
    @Column(length = 20)
    private String referenciaTipo;

    private Long referenciaId;

    @Column(nullable = false)
    private Boolean lida = false;

    private LocalDateTime lidaEm;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        if (lida == null) lida = false;
    }

    public Long getId() { return id; }

    public Long getUsuarioId() { return usuarioId; }
    public void setUsuarioId(Long usuarioId) { this.usuarioId = usuarioId; }

    public String getTipo() { return tipo; }
    public void setTipo(String tipo) { this.tipo = tipo; }

    public String getTitulo() { return titulo; }
    public void setTitulo(String titulo) { this.titulo = titulo; }

    public String getMensagem() { return mensagem; }
    public void setMensagem(String mensagem) { this.mensagem = mensagem; }

    public String getReferenciaTipo() { return referenciaTipo; }
    public void setReferenciaTipo(String referenciaTipo) { this.referenciaTipo = referenciaTipo; }

    public Long getReferenciaId() { return referenciaId; }
    public void setReferenciaId(Long referenciaId) { this.referenciaId = referenciaId; }

    public Boolean getLida() { return lida != null && lida; }
    public void setLida(Boolean lida) { this.lida = lida; }

    public LocalDateTime getLidaEm() { return lidaEm; }
    public void setLidaEm(LocalDateTime lidaEm) { this.lidaEm = lidaEm; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
