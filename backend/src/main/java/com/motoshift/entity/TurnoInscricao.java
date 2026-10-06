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
 * Desde a V5/V6 é aqui — e só aqui — que mora o pagamento de cada entregador:
 * a inscrição é a identidade de "esta pessoa neste turno", e é por ela que a
 * liquidação é chaveada ({@code liquidacao:inscricao:{id}:debito|credito}).
 *
 * status: aceito | finalizado | faltou | cancelado (ver StatusInscricao)
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
        @Index(name = "ix_inscricao_motoboy", columnList = "motoboyId, status"),
        // Pontualidade dos últimos 90 dias (V16).
        @Index(name = "ix_inscricao_checkin", columnList = "motoboyId, checkinEm"),
        // "Cancelou algo nos últimos 30 dias?" — o selo e a análise de score (V22).
        @Index(name = "ix_inscricao_cancelado_por", columnList = "canceladoPorId, canceladoEm")
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

    /**
     * Pagamento deste entregador: null (turno não finalizado) | pendente | pago.
     *
     * <p>Na prática PENDENTE é um instante: a finalização marca pendente,
     * liquida e marca pago dentro da mesma transação. O estado continua
     * existindo porque é ele que distingue "ainda não finalizou" (null) de
     * "finalizou" — e porque linhas antigas, de quando o pagamento dependia de
     * confirmação humana, ficaram paradas em pendente.
     */
    private StatusPagamento pagamentoStatus;

    // As colunas lojista_confirmou_em e motoboy_confirmou_em foram removidas
    // pela V13. Elas guardavam a dupla confirmação — cada parte declarando que
    // o dinheiro tinha mudado de mãos fora do app —, que deixou de existir
    // quando a liquidação passou a ser automática: o lojista compromete o valor
    // ao publicar e a finalização transfere o que já estava reservado.

    // ── Presença (V16) ────────────────────────────────────────────────────
    // O horário REAL deste entregador neste turno. Mora na inscrição, e não
    // no turno, porque num turno multi-vaga cada um chega na sua hora. Quem
    // escreve é o CheckinService; o CHECK da V16 garante que a saída nunca
    // vem antes da chegada.

    /** Quando tocou "Cheguei". Nulo = ainda não chegou (ou turno anterior à V16). */
    private LocalDateTime checkinEm;

    /** De onde fez o check-in — a distância até o turno é conferida na hora. */
    private Double checkinLatitude;
    private Double checkinLongitude;

    /** Quando tocou "Encerrar turno". Só existe depois do check-in. */
    private LocalDateTime checkoutEm;

    // ── Quem cancelou esta inscrição (V22) ────────────────────────────────
    // O próprio entregador, quando desiste da vaga; o lojista, quando cancela
    // o turno. Mora na inscrição porque desistir não cancela o turno — a vaga
    // reabre e o turno segue —, então turnos.cancelado_por_id não registra a
    // desistência. É daqui que o selo "30 dias sem cancelar" e a análise de
    // score leem. Nulos na inscrição que não foi cancelada.
    private Long canceladoPorId;
    private LocalDateTime canceladoEm;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        if (status == null) status = StatusInscricao.ACEITO;
    }

    /** Cancela a inscrição, registrando quem a cancelou e quando. */
    public void cancelar(Long quem, LocalDateTime quando) {
        this.status = StatusInscricao.CANCELADO;
        this.canceladoPorId = quem;
        this.canceladoEm = quando;
    }

    /** O entregador saiu por conta própria — e não o lojista que cancelou o turno. */
    public boolean foiDesistencia() {
        return status == StatusInscricao.CANCELADO && motoboyId != null
                && motoboyId.equals(canceladoPorId);
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

    public LocalDateTime getCheckinEm() { return checkinEm; }
    public void setCheckinEm(LocalDateTime checkinEm) { this.checkinEm = checkinEm; }

    public Double getCheckinLatitude() { return checkinLatitude; }
    public void setCheckinLatitude(Double v) { this.checkinLatitude = v; }

    public Double getCheckinLongitude() { return checkinLongitude; }
    public void setCheckinLongitude(Double v) { this.checkinLongitude = v; }

    public LocalDateTime getCheckoutEm() { return checkoutEm; }
    public void setCheckoutEm(LocalDateTime checkoutEm) { this.checkoutEm = checkoutEm; }

    public Long getCanceladoPorId() { return canceladoPorId; }
    public void setCanceladoPorId(Long canceladoPorId) { this.canceladoPorId = canceladoPorId; }

    public LocalDateTime getCanceladoEm() { return canceladoEm; }
    public void setCanceladoEm(LocalDateTime canceladoEm) { this.canceladoEm = canceladoEm; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
