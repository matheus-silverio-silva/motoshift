package com.motoshift.service;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * Cancelar e desistir, cada um com a sua regra (SCRUM-26).
 *
 * <p>"Cancelar" era um botão só para os dois lados, e fazia a mesma coisa para
 * os dois: derrubava o turno inteiro e, faltando menos de 1h, tirava 0,5 do
 * score do primeiro inscrito — fosse quem fosse que tivesse cancelado. Dois
 * defeitos saíam daí, e são os dois primeiros testes daqui:
 * <ul>
 *   <li>a loja cancelava em cima da hora e o entregador pagava;</li>
 *   <li>um entregador saía de um turno de várias vagas e os colegas perdiam o
 *       turno.</li>
 * </ul>
 *
 * <p>Contra um banco, com os serviços de verdade: o que importa é o conjunto —
 * inscrição, turno, score, reserva e notificação terminando coerentes.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class CancelarEDesistirTest {

    @Autowired private TurnoService turnos;
    @Autowired private CheckinService checkins;
    @Autowired private Reputacao reputacao;
    @Autowired private Selos selos;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private CenarioFinanceiro cenario;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;

    private Usuario loja;
    private Usuario primeiro;
    private Usuario segundo;

    @BeforeEach
    void contas() {
        loja = cenario.conta("lojista", "Loja do Cancelamento", "11222333000144");
        primeiro = cenario.conta("motoboy", "Primeiro Inscrito", "12345678900");
        segundo = cenario.conta("motoboy", "Segundo Inscrito", "98765432100");
        cenario.recarregar(loja.getId(), "1000.00");
    }

    // ── A loja cancela ──────────────────────────────────────────────────────

    @Nested
    @DisplayName("cancelar (a loja)")
    class Cancelar {

        @Test
        @DisplayName("em cima da hora: o turno cai, a reserva volta e NINGUÉM é penalizado")
        void lojaCancelaTarde_ninguemEPenalizado() {
            Turno t = turnoLotado(2, daquiA(30));

            turnos.cancelar(t.getId(), loja.getId());

            // Nem o primeiro inscrito (que levava a penalidade), nem o segundo.
            assertThat(score(primeiro)).isEqualTo(Reputacao.SCORE_INICIAL);
            assertThat(score(segundo)).isEqualTo(Reputacao.SCORE_INICIAL);

            Turno cancelado = recarregar(t);
            assertThat(cancelado.getStatus()).isEqualTo(StatusTurno.CANCELADO);
            assertThat(cancelado.getCanceladoPorId()).isEqualTo(loja.getId());

            // As duas inscrições caem — e dizem que foi a loja.
            assertThat(inscricaoRepo.findByTurnoId(t.getId())).hasSize(2).allSatisfy(i -> {
                assertThat(i.getStatus()).isEqualTo(StatusInscricao.CANCELADO);
                assertThat(i.getCanceladoPorId()).isEqualTo(loja.getId());
                assertThat(i.getCanceladoEm()).isNotNull();
                assertThat(i.foiDesistencia()).isFalse();
            });

            // A reserva voltou inteira.
            assertThat(carteira(loja).getSaldoDisponivel()).isEqualByComparingTo("1000.00");
            assertThat(carteira(loja).getSaldoBloqueado()).isEqualByComparingTo("0.00");

            // Os dois entregadores ficam sabendo, e não só o primeiro.
            assertThat(avisos(primeiro, "turno_cancelado")).hasSize(1);
            assertThat(avisos(segundo, "turno_cancelado")).singleElement()
                    .satisfies(n -> assertThat(n.getMensagem()).contains("pela loja"));

            consistencia.verificarConsistencia(List.of(loja.getId(), primeiro.getId(), segundo.getId()))
                    .exigirConsistente();
        }

        @Test
        @DisplayName("o cancelamento da loja não conta contra o entregador no selo nem no histórico")
        void lojaCancela_naoViraHistoricoDeDesistencia() {
            Turno t = turnoLotado(1, daquiA(30));

            turnos.cancelar(t.getId(), loja.getId());

            assertThat(inscricaoRepo.existsByCanceladoPorIdAndCanceladoEmAfter(
                    primeiro.getId(), LocalDateTime.now().minusDays(30))).isFalse();
            assertThat(inscricaoRepo.desistenciasDe(primeiro.getId())).isEmpty();
        }

        @Test
        @DisplayName("o entregador não cancela o turno: 403, e nada muda")
        void entregadorNaoCancela() {
            Turno t = turnoLotado(2, daquiA(30));

            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.cancelar(t.getId(), primeiro.getId()))
                    .satisfies(e -> {
                        assertThat(e.getStatusCode().value()).isEqualTo(403);
                        assertThat(e.getReason()).contains("Desistir da vaga");
                    });

            assertThat(recarregar(t).getStatus()).isEqualTo(StatusTurno.ACEITO);
            assertThat(score(primeiro)).isEqualTo(Reputacao.SCORE_INICIAL);
        }

        @Test
        @DisplayName("outra loja não cancela o turno alheio: 403")
        void outraLojaNaoCancela() {
            Turno t = turnoLotado(1, daquiA(180));
            Usuario outra = cenario.conta("lojista", "Outra Loja", "99888777000166");

            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.cancelar(t.getId(), outra.getId()))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));
        }
    }

    // ── O entregador desiste ────────────────────────────────────────────────

    @Nested
    @DisplayName("desistir (o entregador)")
    class Desistir {

        @Test
        @DisplayName("o 2º desiste em cima da hora: só ele é penalizado, e o turno segue com o 1º")
        void segundoDesisteTarde_soEleEPenalizado() {
            Turno t = turnoLotado(2, daquiA(30));

            turnos.desistir(t.getId(), segundo.getId());

            assertThat(score(segundo)).isEqualTo(4.5);
            assertThat(score(primeiro)).as("o colega de vaga não paga pela saída do outro")
                    .isEqualTo(Reputacao.SCORE_INICIAL);

            // O turno continua — com o primeiro —, e a vaga reabre.
            Turno depois = recarregar(t);
            assertThat(depois.getStatus()).isEqualTo(StatusTurno.ABERTO);
            assertThat(depois.getMotoboyId()).isEqualTo(primeiro.getId());
            assertThat(depois.getCanceladoPorId()).isNull();
            assertThat(inscricao(t, primeiro).getStatus()).isEqualTo(StatusInscricao.ACEITO);

            TurnoInscricao saiu = inscricao(t, segundo);
            assertThat(saiu.getStatus()).isEqualTo(StatusInscricao.CANCELADO);
            assertThat(saiu.getCanceladoPorId()).isEqualTo(segundo.getId());
            assertThat(saiu.getCanceladoEm()).isNotNull();
            assertThat(saiu.foiDesistencia()).isTrue();

            // A reserva continua bloqueada inteira: a vaga existe, só ficou sem dono.
            assertThat(carteira(loja).getSaldoBloqueado()).isEqualByComparingTo("200.00");

            // A loja é avisada, com o nome de quem saiu e o turno.
            assertThat(avisos(loja, "entregador_desistiu")).singleElement()
                    .satisfies(n -> assertThat(n.getMensagem())
                            .contains("Segundo Inscrito desistiu da vaga no turno")
                            .contains(t.getTitulo()));

            // E a resposta do turno mostra a vaga livre de novo.
            assertThat(turnos.aceitar(t.getId(), terceiro().getId()).getVagasPreenchidas())
                    .isEqualTo(2);
        }

        @Test
        @DisplayName("o principal desiste: o posto passa ao próximo inscrito ativo — ou fica vazio")
        void principalDesiste_oPrincipalMuda() {
            Turno t = turnoLotado(2, daquiA(60 * 24));
            assertThat(recarregar(t).getMotoboyId()).isEqualTo(primeiro.getId());

            turnos.desistir(t.getId(), primeiro.getId());

            assertThat(recarregar(t).getMotoboyId()).isEqualTo(segundo.getId());
            // Com um dia de folga, desistir não custa nada.
            assertThat(score(primeiro)).isEqualTo(Reputacao.SCORE_INICIAL);

            turnos.desistir(t.getId(), segundo.getId());

            Turno vazio = recarregar(t);
            assertThat(vazio.getMotoboyId()).isNull();
            assertThat(vazio.getStatus()).isEqualTo(StatusTurno.ABERTO);
            // Ninguém mais no turno, e a reserva segue lá: o turno continua
            // publicado, esperando entregador.
            assertThat(carteira(loja).getSaldoBloqueado()).isEqualByComparingTo("200.00");
        }

        @Test
        @DisplayName("depois do check-in não há desistência: 409")
        void depoisDoCheckin_409() {
            Turno t = turnoLotado(1, daquiA(20));
            checkins.checkin(t.getId(), primeiro.getId(), null, null);

            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.desistir(t.getId(), primeiro.getId()))
                    .satisfies(e -> {
                        assertThat(e.getStatusCode().value()).isEqualTo(409);
                        assertThat(e.getReason()).contains("já fez check-in");
                    });

            assertThat(inscricao(t, primeiro).getStatus()).isEqualTo(StatusInscricao.ACEITO);
            assertThat(score(primeiro)).isEqualTo(Reputacao.SCORE_INICIAL);
        }

        @Test
        @DisplayName("a desistência tira o selo '30 dias sem cancelar' e vira histórico — mesmo sem custar score")
        void desistenciaContaParaOSelo() {
            // Um turno concluído há 40 dias: sem ele o selo nem estaria em jogo.
            turnoConcluidoHa(40);
            assertThat(codigos(primeiro)).contains("sem_cancelar");

            Turno t = turnoLotado(1, daquiA(60 * 24));
            turnos.desistir(t.getId(), primeiro.getId());

            assertThat(score(primeiro)).isEqualTo(Reputacao.SCORE_INICIAL);
            assertThat(codigos(primeiro)).doesNotContain("sem_cancelar");
            assertThat(inscricaoRepo.desistenciasDe(primeiro.getId())).singleElement()
                    .satisfies(d -> assertThat(d.turnoId()).isEqualTo(t.getId()));
        }

        @Test
        @DisplayName("quem desistiu não aceita o mesmo turno de novo: 409, não 500")
        void naoAceitaDeNovo() {
            Turno t = turnoLotado(1, daquiA(60 * 24));
            turnos.desistir(t.getId(), primeiro.getId());

            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.aceitar(t.getId(), primeiro.getId()))
                    .satisfies(e -> {
                        assertThat(e.getStatusCode().value()).isEqualTo(409);
                        assertThat(e.getReason()).contains("desistiu deste turno");
                    });
        }

        @Test
        @DisplayName("quem não tem vaga no turno não desiste: 403")
        void semVaga_403() {
            Turno t = turnoLotado(1, daquiA(60 * 24));

            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.desistir(t.getId(), segundo.getId()))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));
            // Nem o lojista do turno: desistir é de quem tem vaga.
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.desistir(t.getId(), loja.getId()))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));
        }

        @Test
        @DisplayName("depois do início a vaga não reabre: o turno segue fechado, e a desistência custa")
        void depoisDoInicio_naoReabre() {
            Turno t = turnoLotado(2, daquiA(30));
            moverInicio(t, LocalDateTime.now().minusMinutes(5));

            turnos.desistir(t.getId(), segundo.getId());

            assertThat(recarregar(t).getStatus()).isEqualTo(StatusTurno.ACEITO);
            assertThat(score(segundo)).isEqualTo(4.5);
        }

        @Test
        @DisplayName("turno encerrado não tem do que desistir: 409")
        void turnoEncerrado_409() {
            Turno t = turnoLotado(1, daquiA(60 * 24));
            turnos.cancelar(t.getId(), loja.getId());

            // A inscrição já foi cancelada pela loja: ele não tem mais vaga.
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.desistir(t.getId(), primeiro.getId()))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));

            Turno pago = cenario.turnoPago(loja.getId(), "80.00", segundo.getId());
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> turnos.desistir(pago.getId(), segundo.getId()))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(409));
        }
    }

    // ── apoio ───────────────────────────────────────────────────────────────

    /** Daqui a [minutos], no minuto cheio. */
    private static LocalDateTime daquiA(int minutos) {
        return LocalDateTime.now().plusMinutes(minutos).truncatedTo(ChronoUnit.MINUTES);
    }

    /**
     * Turno de R$ 100 por vaga, aceito PELO SERVIÇO por {@code vagas}
     * entregadores (primeiro, depois segundo) — lotado, portanto ACEITO — e
     * com o início trazido para {@code inicio}.
     */
    private Turno turnoLotado(int vagas, LocalDateTime inicio) {
        Turno t = cenario.publicar(loja.getId(), "100.00", vagas);
        turnos.aceitar(t.getId(), primeiro.getId());
        if (vagas > 1) turnos.aceitar(t.getId(), segundo.getId());
        moverInicio(t, inicio);
        Turno lotado = recarregar(t);
        assertThat(lotado.getStatus()).isEqualTo(StatusTurno.ACEITO);
        return lotado;
    }

    private void moverInicio(Turno t, LocalDateTime inicio) {
        Turno atual = recarregar(t);
        atual.setDataInicio(inicio);
        atual.setDataFim(inicio.plusHours(4));
        turnoRepo.save(atual);
    }

    /** Um turno que o primeiro concluiu há [dias] dias — histórico para o selo. */
    private void turnoConcluidoHa(int dias) {
        Turno t = cenario.turnoPago(loja.getId(), "80.00", primeiro.getId());
        LocalDateTime inicio = LocalDateTime.now().minusDays(dias);
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        turnoRepo.save(t);
    }

    private Usuario terceiro() {
        return cenario.conta("motoboy", "Terceiro", "11122233344");
    }

    private Turno recarregar(Turno t) {
        return turnoRepo.findById(t.getId()).orElseThrow();
    }

    private TurnoInscricao inscricao(Turno t, Usuario quem) {
        return inscricaoRepo.findByTurnoIdAndMotoboyId(t.getId(), quem.getId()).orElseThrow();
    }

    private Double score(Usuario u) {
        return usuarioRepo.findById(u.getId()).orElseThrow().getScore();
    }

    private Carteira carteira(Usuario u) {
        return carteiraRepo.findByUsuarioId(u.getId()).orElseThrow();
    }

    private List<String> codigos(Usuario u) {
        return selos.de(usuarioRepo.findById(u.getId()).orElseThrow()).stream()
                .map(Selos.Selo::codigo).toList();
    }

    private List<Notificacao> avisos(Usuario u, String tipo) {
        return notificacaoRepo.findAll().stream()
                .filter(n -> n.getUsuarioId().equals(u.getId()) && tipo.equals(n.getTipo()))
                .toList();
    }
}
