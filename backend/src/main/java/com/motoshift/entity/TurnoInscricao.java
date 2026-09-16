package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Inscrição de um motoboy em um turno.
 *
 * Um turno pode ter várias vagas (campo {@code vagas} em {@link Turno}); cada
 * motoboy que aceita gera uma inscrição. Isso permite que o lojista tenha
 * vários entregadores no mesmo horário, sem quebrar a modelagem existente
 * (o turno mantém {@code motoboyId} apontando para o primeiro inscrito).
 *
 * Desde a V5/V6 é aqui — e só aqui — que mora a dupla confirmação do
 * pagamento: cada entregador é pago pela própria inscrição.
 *
 * status: aceito | finalizado | cancelado (ver StatusInscricao)
 */
@Entity
@Table(
    name = "turno_inscricoes",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_turno_motoboy",
        columnNames = {"turnoId", "motoboyId"}
    ),
    indexes = {
        // "Turnos deste entregador": a unicidade acima começa por turnoId e
        // não serve para buscar por motoboy (V11).
        @Index(name = "ix_inscricao_motoboy", columnList = "motoboyId, status")
    }
)
public class TurnoInscricao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long turnoId;

    @Column(nullable = false)
    private Long motoboyId;

    @Column(nullable = false)
    private StatusInscricao status = StatusInscricao.ACEITO;

    // Pagamento deste entregador, com a dupla confirmação (lojista pagou +
    // entregador recebeu): null (turno não finalizado) | pendente | pago
    private StatusPagamento pagamentoStatus;
    private LocalDateTime lojistaConfirmouEm;
    private LocalDateTime motoboyConfirmouEm;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        if (status == null) status = StatusInscricao.ACEITO;
    }

    public Long getId() { return id; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public Long getMotoboyId() { return motoboyId; }
    public void setMotoboyId(Long motoboyId) { this.motoboyId = motoboyId; }

    public StatusInscricao getStatus() { return status; }
    public void setStatus(StatusInscricao status) { this.status = status; }

    public StatusPagamento getPagamentoStatus() { return pagamentoStatus; }
    public void setPagamentoStatus(StatusPagamento p) { this.pagamentoStatus = p; }

    public LocalDateTime getLojistaConfirmouEm() { return lojistaConfirmouEm; }
    public void setLojistaConfirmouEm(LocalDateTime t) { this.lojistaConfirmouEm = t; }

    public LocalDateTime getMotoboyConfirmouEm() { return motoboyConfirmouEm; }
    public void setMotoboyConfirmouEm(LocalDateTime t) { this.motoboyConfirmouEm = t; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
