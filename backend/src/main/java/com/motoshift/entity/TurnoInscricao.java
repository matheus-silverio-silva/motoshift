package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Inscrição de um motoboy em um turno.
 *
 * Um turno pode ter várias vagas (campo {@code vagas} em {@link Turno}); cada
 * motoboy que aceita gera uma inscrição. Isso permite que o lojista tenha
 * vários entregadores no mesmo horário, sem quebrar a modelagem existente
 * (o turno mantém {@code motoboyId} apontando para o primeiro inscrito, por
 * compatibilidade com os fluxos atuais de finalização/pagamento).
 *
 * status: aceito | finalizado | cancelado (ver StatusInscricao)
 */
@Entity
@Table(
    name = "turno_inscricoes",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_turno_motoboy",
        columnNames = {"turnoId", "motoboyId"}
    )
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

    // Pagamento por entregador (dupla confirmação, igual ao fluxo do turno):
    // null (turno não finalizado) | pendente | pago
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
