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

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
