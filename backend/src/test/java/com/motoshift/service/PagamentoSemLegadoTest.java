package com.motoshift.service;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * A liquidação depois que o caminho legado morreu (V5).
 *
 * O pagamento tinha dois caminhos: o da inscrição e um "fallback" que gravava a
 * dupla confirmação no próprio turno. O fallback era invisível — quando a
 * inscrição não era encontrada, o serviço mudava de rota em silêncio e creditava
 * dinheiro pelo outro lado. Este teste fixa as duas metades do que mudou:
 *
 *   1. o dinheiro anda inteiro pela inscrição — que depois da V6 é o único
 *      lugar onde a dupla confirmação existe;
 *   2. turno sem inscrição não tem plano B — falha alto.
 *
 * Roda com o contexto de verdade porque o que se quer provar é a transação
 * completa: inscrição paga, turno pago e saldo creditado no mesmo caminho.
 */
@SpringBootTest
@ActiveProfiles("test")
class PagamentoSemLegadoTest {

    // Ids altos para não colidirem com a massa do DataInitializer.
    private static final Long LOJISTA = 950_001L;
    private static final Long MOTOBOY = 950_002L;

    @Autowired private PagamentoTurnoService pagamentos;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;

    @Test
    @DisplayName("as duas confirmações liquidam a inscrição e creditam a carteira")
    void liquidaPelaInscricao() {
        Turno turno = turnoFinalizado(MOTOBOY);
        TurnoInscricao ins = inscricaoPendente(turno, MOTOBOY);
        BigDecimal saldoAntes = saldoDe(MOTOBOY);

        pagamentos.confirmarPagamentoLojista(turno.getId(), LOJISTA, MOTOBOY);
        pagamentos.confirmarRecebimentoMotoboy(turno.getId(), MOTOBOY);

        TurnoInscricao relida = inscricaoRepo.findById(ins.getId()).orElseThrow();
        assertThat(relida.getPagamentoStatus()).isEqualTo(StatusPagamento.PAGO);
        assertThat(relida.getLojistaConfirmouEm()).isNotNull();
        assertThat(relida.getMotoboyConfirmouEm()).isNotNull();

        Turno turnoRelido = turnoRepo.findById(turno.getId()).orElseThrow();
        assertThat(turnoRelido.getPagamentoStatus()).isEqualTo(StatusPagamento.PAGO);

        assertThat(saldoDe(MOTOBOY)).isEqualByComparingTo(saldoAntes.add(new BigDecimal("120.00")));
    }

    @Test
    @DisplayName("turno sem inscrição falha alto — não existe mais rota alternativa")
    void semInscricao_naoTemPlanoB() {
        Turno turno = turnoFinalizado(MOTOBOY); // sem inscrição nenhuma
        BigDecimal saldoAntes = saldoDe(MOTOBOY);

        assertThatExceptionOfType(IllegalStateException.class)
                .isThrownBy(() -> pagamentos.confirmarPagamentoLojista(
                        turno.getId(), LOJISTA, MOTOBOY))
                .withMessageContaining(String.valueOf(turno.getId()));

        // E o mais importante: ninguém foi pago pelo caminho de trás.
        assertThat(saldoDe(MOTOBOY)).isEqualByComparingTo(saldoAntes);
        Turno relido = turnoRepo.findById(turno.getId()).orElseThrow();
        assertThat(relido.getPagamentoStatus()).isEqualTo(StatusPagamento.PENDENTE);
    }

    @Test
    @DisplayName("quem não é do turno continua levando 403, e não 500")
    void estranhoAoTurno_continua403() {
        Turno turno = turnoFinalizado(MOTOBOY);
        inscricaoPendente(turno, MOTOBOY);

        // Distinção que a morte do fallback precisa preservar: pedir o que não é
        // seu é 403 (erro de quem chamou); inscrição faltando é 500 (erro nosso).
        assertThatExceptionOfType(org.springframework.web.server.ResponseStatusException.class)
                .isThrownBy(() -> pagamentos.confirmarRecebimentoMotoboy(turno.getId(), 950_999L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));
    }

    // ── Fixtures ─────────────────────────────────────────────

    private Turno turnoFinalizado(Long motoboyId) {
        Turno t = new Turno();
        t.setLojistId(LOJISTA);
        t.setMotoboyId(motoboyId);
        t.setTitulo("Turno para liquidar");
        t.setDataInicio(LocalDateTime.now().minusDays(1));
        t.setDataFim(LocalDateTime.now().minusDays(1).plusHours(4));
        t.setValorEstimado(new BigDecimal("120.00"));
        t.setStatus(StatusTurno.FINALIZADO);
        t.setPagamentoStatus(StatusPagamento.PENDENTE);
        return turnoRepo.save(t);
    }

    private TurnoInscricao inscricaoPendente(Turno turno, Long motoboyId) {
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(turno.getId());
        ins.setMotoboyId(motoboyId);
        ins.setStatus(StatusInscricao.FINALIZADO);
        ins.setPagamentoStatus(StatusPagamento.PENDENTE);
        return inscricaoRepo.save(ins);
    }

    private BigDecimal saldoDe(Long usuarioId) {
        return carteiraRepo.findByUsuarioId(usuarioId)
                .map(Carteira::getSaldoDisponivel)
                .orElse(BigDecimal.ZERO);
    }
}
