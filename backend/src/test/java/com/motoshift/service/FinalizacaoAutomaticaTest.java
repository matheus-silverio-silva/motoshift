package com.motoshift.service;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Turno esquecido se finaliza sozinho (SCRUM-31).
 *
 * <p>O job só cobrava a finalização por notificação. Bastava as duas partes
 * esquecerem o turno e o dinheiro ficava reservado na carteira do lojista
 * para sempre — e o entregador que trabalhou, sem receber.
 *
 * <p>O prazo é o padrão, 12 horas depois do FIM do turno
 * ({@code motoshift.finalizacao.automatica-horas}). Os três casos pedidos: com
 * check-in, sem nenhum check-in e dentro do prazo.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class FinalizacaoAutomaticaTest {

    @Autowired private TurnoExpiracaoService job;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private CenarioFinanceiro cenario;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    private Usuario loja;
    private Usuario trabalhou;
    private Usuario faltou;

    @BeforeEach
    void contas() {
        loja = cenario.conta("lojista", "Loja Esquecida", "11222333000144");
        trabalhou = cenario.conta("motoboy", "Quem Trabalhou", "12345678900");
        faltou = cenario.conta("motoboy", "Quem Faltou", "98765432100");
        cenario.recarregar(loja.getId(), "1000.00");
    }

    @Test
    @DisplayName("com check-in: 13h depois do fim, o job finaliza, paga quem chegou e devolve a parte de quem faltou")
    void comCheckin_finalizaEPaga() {
        Turno t = turnoEsquecido(2, 13, StatusTurno.EM_ANDAMENTO);
        inscrever(t, trabalhou, true);
        inscrever(t, faltou, false);

        int fechados = job.finalizarTurnosEsquecidos();

        assertThat(fechados).isGreaterThanOrEqualTo(1);
        Turno depois = recarregar(t);
        assertThat(depois.getStatus()).isEqualTo(StatusTurno.FINALIZADO);
        assertThat(depois.getPagamentoStatus()).isEqualTo(StatusPagamento.PAGO);
        assertThat(depois.getMotoboyId()).isEqualTo(trabalhou.getId());

        // As regras de pagamento são as de "Finalizar": só quem fez check-in.
        assertThat(carteira(trabalhou).getSaldoDisponivel()).isEqualByComparingTo("100.00");
        assertThat(saldo(faltou)).isEqualByComparingTo("0.00");
        assertThat(inscricao(t, trabalhou).getStatus()).isEqualTo(StatusInscricao.FINALIZADO);
        assertThat(inscricao(t, faltou).getStatus()).isEqualTo(StatusInscricao.FALTOU);

        // 200 reservados, 100 pagos, 100 de volta: nada preso.
        assertThat(carteira(loja).getSaldoBloqueado()).isEqualByComparingTo("0.00");
        assertThat(carteira(loja).getSaldoDisponivel()).isEqualByComparingTo("900.00");

        // As duas partes ficam sabendo — e quem faltou também.
        assertThat(avisos(loja, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).singleElement()
                .satisfies(n -> assertThat(n.getMensagem())
                        .contains("há mais de 12 horas").contains("foi pago"));
        assertThat(avisos(trabalhou, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).singleElement()
                .satisfies(n -> assertThat(n.getMensagem()).contains("creditado na sua carteira"));
        assertThat(avisos(faltou, "turno_falta")).hasSize(1);
        assertThat(avisos(faltou, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).isEmpty();

        conferirOCenario();
    }

    @Test
    @DisplayName("sem nenhum check-in: as inscrições viram FALTOU, a reserva volta inteira e o turno vai para EXPIRADO")
    void semCheckin_devolveTudoEExpira() {
        Turno t = turnoEsquecido(2, 13, StatusTurno.ACEITO);
        inscrever(t, trabalhou, false);
        inscrever(t, faltou, false);

        job.finalizarTurnosEsquecidos();

        Turno depois = recarregar(t);
        assertThat(depois.getStatus()).isEqualTo(StatusTurno.EXPIRADO);
        assertThat(depois.getExpiradoEm()).isNotNull();
        assertThat(depois.getPagamentoStatus()).isNull();
        assertThat(depois.getMotoboyId()).as("ninguém trabalhou neste turno").isNull();

        assertThat(inscricaoRepo.findByTurnoId(t.getId())).hasSize(2)
                .allSatisfy(i -> {
                    assertThat(i.getStatus()).isEqualTo(StatusInscricao.FALTOU);
                    assertThat(i.getPagamentoStatus()).isNull();
                });

        // Ninguém recebeu, e a reserva voltou INTEIRA — com o motivo próprio.
        assertThat(saldo(trabalhou)).isEqualByComparingTo("0.00");
        assertThat(saldo(faltou)).isEqualByComparingTo("0.00");
        assertThat(carteira(loja).getSaldoBloqueado()).isEqualByComparingTo("0.00");
        assertThat(carteira(loja).getSaldoDisponivel()).isEqualByComparingTo("1000.00");

        Transacao devolucao = transacaoRepo
                .findByIdempotencyKey("liberacao:turno:" + t.getId() + ":sem_checkin").orElseThrow();
        assertThat(devolucao.getTipo()).isEqualTo(TipoTransacao.LIBERACAO_RESERVA);
        assertThat(devolucao.getValor()).isEqualByComparingTo("200.00");
        assertThat(devolucao.getDescricao()).contains("sem check-in");
        assertThat(transacaoRepo.findByTurnoId(t.getId()))
                .noneMatch(x -> x.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO);

        // Faltar não custa score (decisão da Fase 2).
        assertThat(usuarioRepo.findById(faltou.getId()).orElseThrow().getScore())
                .isEqualTo(Reputacao.SCORE_INICIAL);

        assertThat(avisos(loja, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).singleElement()
                .satisfies(n -> assertThat(n.getMensagem())
                        .contains("sem nenhum check-in").contains("voltou inteira"));
        assertThat(avisos(trabalhou, "turno_falta")).hasSize(1);
        assertThat(avisos(faltou, "turno_falta")).hasSize(1);

        conferirOCenario();
    }

    @Test
    @DisplayName("dentro do prazo: turno que terminou há 11h não é tocado")
    void dentroDoPrazo_naoETocado() {
        Turno comCheckin = turnoEsquecido(1, 11, StatusTurno.EM_ANDAMENTO);
        inscrever(comCheckin, trabalhou, true);
        Turno semCheckin = turnoEsquecido(1, 11, StatusTurno.ACEITO);
        inscrever(semCheckin, faltou, false);

        job.finalizarTurnosEsquecidos();

        assertThat(recarregar(comCheckin).getStatus()).isEqualTo(StatusTurno.EM_ANDAMENTO);
        assertThat(recarregar(semCheckin).getStatus()).isEqualTo(StatusTurno.ACEITO);
        assertThat(inscricao(comCheckin, trabalhou).getStatus()).isEqualTo(StatusInscricao.ACEITO);
        assertThat(inscricao(semCheckin, faltou).getStatus()).isEqualTo(StatusInscricao.ACEITO);
        // A reserva dos dois continua bloqueada, e ninguém foi pago nem avisado.
        assertThat(carteira(loja).getSaldoBloqueado()).isEqualByComparingTo("200.00");
        assertThat(saldo(trabalhou)).isEqualByComparingTo("0.00");
        assertThat(avisos(loja, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).isEmpty();
    }

    @Test
    @DisplayName("o job é idempotente: rodar de novo não paga nem avisa de novo")
    void rodarDeNovo_naoRepete() {
        Turno t = turnoEsquecido(1, 13, StatusTurno.EM_ANDAMENTO);
        inscrever(t, trabalhou, true);

        job.finalizarTurnosEsquecidos();
        job.finalizarTurnosEsquecidos();

        assertThat(carteira(trabalhou).getSaldoDisponivel()).isEqualByComparingTo("100.00");
        assertThat(transacaoRepo.findByTurnoId(t.getId()))
                .filteredOn(x -> x.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO).hasSize(1);
        assertThat(avisos(loja, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).hasSize(1);
        assertThat(avisos(trabalhou, TurnoService.TIPO_FINALIZACAO_AUTOMATICA)).hasSize(1);
    }

    @Test
    @DisplayName("turno aberto, finalizado ou cancelado não é assunto deste job")
    void soAceitoOuEmAndamento() {
        Turno aberto = turnoEsquecido(1, 20, StatusTurno.ABERTO);
        Turno cancelado = turnoEsquecido(1, 20, StatusTurno.CANCELADO);

        job.finalizarTurnosEsquecidos();

        assertThat(recarregar(aberto).getStatus()).isEqualTo(StatusTurno.ABERTO);
        assertThat(recarregar(cancelado).getStatus()).isEqualTo(StatusTurno.CANCELADO);
    }

    @Test
    @DisplayName("prazo menor que 1 hora é recusado na subida, em vez de finalizar o turno no minuto em que termina")
    void prazoInvalido_falhaAoConstruir() {
        assertThatThrownBy(() -> new TurnoExpiracaoService(null, null, null, null, null, 0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("motoshift.finalizacao.automatica-horas");
    }

    // ── apoio ───────────────────────────────────────────────────────────────

    /**
     * Turno de R$ 100 por vaga, publicado pelo serviço (reserva de verdade) e
     * depois levado ao passado: terminou há {@code horasDesdeOFim} horas e
     * ninguém finalizou.
     */
    private Turno turnoEsquecido(int vagas, int horasDesdeOFim, StatusTurno status) {
        Turno t = cenario.publicar(loja.getId(), "100.00", vagas);
        LocalDateTime fim = LocalDateTime.now().minusHours(horasDesdeOFim);
        t.setDataInicio(fim.minusHours(4));
        t.setDataFim(fim);
        t.setStatus(status);
        return turnoRepo.save(t);
    }

    private void inscrever(Turno t, Usuario quem, boolean comCheckin) {
        cenario.inscrever(t, quem.getId());
        if (!comCheckin) return;
        TurnoInscricao ins = inscricao(t, quem);
        ins.setCheckinEm(recarregar(t).getDataInicio());
        inscricaoRepo.save(ins);
    }

    private Turno recarregar(Turno t) {
        return turnoRepo.findById(t.getId()).orElseThrow();
    }

    private TurnoInscricao inscricao(Turno t, Usuario quem) {
        return inscricaoRepo.findByTurnoIdAndMotoboyId(t.getId(), quem.getId()).orElseThrow();
    }

    private Carteira carteira(Usuario u) {
        return carteiraRepo.findByUsuarioId(u.getId()).orElseThrow();
    }

    /** O disponível de quem pode nem ter carteira ainda. */
    private BigDecimal saldo(Usuario u) {
        return carteiraRepo.findByUsuarioId(u.getId())
                .map(Carteira::getSaldoDisponivel).orElse(BigDecimal.ZERO);
    }

    private List<Notificacao> avisos(Usuario u, String tipo) {
        return notificacaoRepo.findAll().stream()
                .filter(n -> n.getUsuarioId().equals(u.getId()) && tipo.equals(n.getTipo()))
                .toList();
    }

    private void conferirOCenario() {
        consistencia.verificarConsistencia(
                List.of(loja.getId(), trabalhou.getId(), faltou.getId())).exigirConsistente();
    }
}
