package com.motoshift.service;

import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.support.CenarioFinanceiro;
import com.motoshift.support.Rumo;
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
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Check-in e check-out (V16): janela, distância, papel, a passagem a
 * EM_ANDAMENTO, e o que deixa de valer depois que o turno começou.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class CheckinServiceTest {

    // O ponto do turno: a loja do Água Verde.
    private static final double LAT = -25.4560;
    private static final double LNG = -49.2820;

    @Autowired private CenarioFinanceiro cenario;
    @Autowired private CheckinService checkins;
    @Autowired private TurnoService turnos;
    @Autowired private TurnoConsultaService consultas;
    @Autowired private TurnoExpiracaoService expiracao;
    @Autowired private Reputacao reputacao;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;
    @Autowired private NotificacaoService notificacoes;
    @Autowired private TurnoAcesso acesso;
    @Autowired private TurnoMapper mapper;

    private Usuario loja;
    private Usuario ricardo;
    private Usuario lucas;

    @BeforeEach
    void contas() {
        loja = cenario.conta("lojista", "Cláudia Oliveira", "12.345.678/0001-90");
        ricardo = cenario.conta("motoboy", "Ricardo Souza", "12345678900");
        lucas = cenario.conta("motoboy", "Lucas Mendes", "98765432100");
        cenario.recarregar(loja.getId(), "1000.00");
    }

    // ── janela ──────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("janela: de 30 min antes do início até o fim")
    class Janela {

        @Test
        @DisplayName("31 min antes ainda não abriu; 29 min antes já vale")
        void abreTrintaMinutosAntes() {
            Turno cedo = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(31));
            assertThatThrownBy(() -> checkins.checkin(cedo.getId(), ricardo.getId(), LAT, LNG))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("abre 30 minutos antes");

            Turno quase = turnoAceito(lucas, LocalDateTime.now().plusMinutes(29));
            checkins.checkin(quase.getId(), lucas.getId(), LAT, LNG);
            assertThat(inscricao(quase, lucas).getCheckinEm()).isNotNull();
        }

        @Test
        @DisplayName("depois do fim do turno, não")
        void fechaNoFim() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().minusHours(5));
            // Fim = início + 4h = 1h atrás.
            assertThatThrownBy(() -> checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("já terminou");
        }
    }

    // ── distância ───────────────────────────────────────────────────────────

    @Nested
    @DisplayName("distância até o ponto do turno")
    class Distancia {

        @Test
        @DisplayName("a 400 m entra; a 600 m e a 1,2 km não — e a mensagem diz quanto")
        void raioDe500m() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(10));

            double[] longe = Rumo.destino(LAT, LNG, 0, 1.2);
            assertThatThrownBy(() -> checkins.checkin(t.getId(), ricardo.getId(), longe[0], longe[1]))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("Você está a 1,2 km do local");

            double[] perto = Rumo.destino(LAT, LNG, 90, 0.6);
            assertThatThrownBy(() -> checkins.checkin(t.getId(), ricardo.getId(), perto[0], perto[1]))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("Você está a 600 m do local");

            double[] naPorta = Rumo.destino(LAT, LNG, 180, 0.4);
            checkins.checkin(t.getId(), ricardo.getId(), naPorta[0], naPorta[1]);
            TurnoInscricao ins = inscricao(t, ricardo);
            assertThat(ins.getCheckinEm()).isNotNull();
            assertThat(ins.getCheckinLatitude()).isEqualTo(naPorta[0]);
        }

        @Test
        @DisplayName("sem localização, com a trava ligada, é 400")
        void semLocalizacao() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(10));
            assertThatThrownBy(() -> checkins.checkin(t.getId(), ricardo.getId(), null, null))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("Envie a sua localização");
        }

        @Test
        @DisplayName("com exigir-proximidade=false, vale de casa — a janela continua valendo")
        void travaDesligada() {
            CheckinService deCasa = new CheckinService(turnoRepo, inscricaoRepo, usuarioRepo,
                    notificacoes, acesso, mapper, 500, false);
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(10));

            deCasa.checkin(t.getId(), ricardo.getId(), -23.55, -46.63); // São Paulo
            assertThat(inscricao(t, ricardo).getCheckinEm()).isNotNull();

            Turno cedo = turnoAceito(lucas, LocalDateTime.now().plusHours(2));
            assertThatThrownBy(() -> deCasa.checkin(cedo.getId(), lucas.getId(), null, null))
                    .hasMessageContaining("abre 30 minutos antes");
        }
    }

    // ── papel ───────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("só o entregador inscrito e aceito")
    class Papel {

        @Test
        @DisplayName("o lojista, um entregador de fora e um que cancelou levam 403")
        void soQuemEstaNoTurno() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(10));

            assertThatThrownBy(() -> checkins.checkin(t.getId(), loja.getId(), LAT, LNG))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("inscrito e aceito");
            assertThatThrownBy(() -> checkins.checkin(t.getId(), lucas.getId(), LAT, LNG))
                    .hasMessageContaining("inscrito e aceito");

            TurnoInscricao ins = inscricao(t, ricardo);
            ins.setStatus(StatusInscricao.CANCELADO);
            inscricaoRepo.save(ins);
            assertThatThrownBy(() -> checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG))
                    .hasMessageContaining("inscrito e aceito");
        }

        @Test
        @DisplayName("check-out antes do check-in é recusado")
        void checkoutSoDepois() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(10));
            assertThatThrownBy(() -> checkins.checkout(t.getId(), ricardo.getId()))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("antes de encerrar");
        }
    }

    // ── status e avisos ─────────────────────────────────────────────────────

    @Nested
    @DisplayName("o primeiro check-in começa o turno")
    class Status {

        @Test
        @DisplayName("ACEITO vira EM_ANDAMENTO, e o lojista recebe \"Ricardo chegou às …\"")
        void aceitoViraEmAndamento() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(3));

            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            assertThat(turnoRepo.findById(t.getId()).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.EM_ANDAMENTO);
            List<Notificacao> avisos = avisos(loja, "entregador_chegou");
            assertThat(avisos).hasSize(1);
            assertThat(avisos.get(0).getMensagem())
                    .startsWith("Ricardo chegou às ")
                    .containsPattern("\\((\\d+ min antes|no horário)\\)");
        }

        @Test
        @DisplayName("repetir o check-in não muda a hora nem avisa de novo")
        void idempotente() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(3));
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);
            LocalDateTime primeira = inscricao(t, ricardo).getCheckinEm();

            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            assertThat(inscricao(t, ricardo).getCheckinEm()).isEqualTo(primeira);
            assertThat(avisos(loja, "entregador_chegou")).hasSize(1);
        }

        @Test
        @DisplayName("turno multi-vaga ainda ABERTO antes do início continua aberto às vagas")
        void abertoAntesDoInicio() {
            Turno t = publicar(2, LocalDateTime.now().plusMinutes(20));
            turnos.aceitar(t.getId(), ricardo.getId());

            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            assertThat(turnoRepo.findById(t.getId()).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.ABERTO);
        }

        @Test
        @DisplayName("check-out grava a saída e avisa o lojista, sem finalizar")
        void checkout() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(3));
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            checkins.checkout(t.getId(), ricardo.getId());

            assertThat(inscricao(t, ricardo).getCheckoutEm()).isNotNull();
            assertThat(turnoRepo.findById(t.getId()).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.EM_ANDAMENTO);
            assertThat(avisos(loja, "entregador_saiu")).hasSize(1);
        }
    }

    // ── o que muda depois que começou ───────────────────────────────────────

    @Nested
    @DisplayName("turno em andamento")
    class EmAndamento {

        @Test
        @DisplayName("não é cancelado como se não tivesse começado — nem pelo lojista, nem pelo entregador")
        void naoCancela() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(3));
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            assertThatThrownBy(() -> turnos.cancelar(t.getId(), loja.getId()))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("já começou");
            assertThatThrownBy(() -> turnos.cancelar(t.getId(), ricardo.getId()))
                    .hasMessageContaining("já começou");
        }

        @Test
        @DisplayName("check-in feito antes do início, com vagas ainda abertas, também impede o cancelamento")
        void checkinAdiantadoImpedeCancelamento() {
            Turno t = publicar(2, LocalDateTime.now().plusMinutes(20));
            turnos.aceitar(t.getId(), ricardo.getId());
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            assertThatThrownBy(() -> turnos.cancelar(t.getId(), loja.getId()))
                    .hasMessageContaining("já começou");
        }

        @Test
        @DisplayName("finalizar continua valendo e paga")
        void finaliza() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(3));
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

            turnos.finalizar(t.getId(), loja.getId());

            assertThat(turnoRepo.findById(t.getId()).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.FINALIZADO);
            assertThat(cenario.pagamentoRecebido(t, ricardo.getId())).isNotNull();
        }

        @Test
        @DisplayName("o job de vencimento não toca no turno em andamento")
        void naoVence() {
            Turno t = turnoAceito(ricardo, LocalDateTime.now().plusMinutes(3));
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);
            moverInicio(t, LocalDateTime.now().minusMinutes(30));

            expiracao.expirarTurnosNaoPreenchidos();

            assertThat(turnoRepo.findById(t.getId()).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.EM_ANDAMENTO);
        }

        @Test
        @DisplayName("turno multi-vaga com check-in: no início, o job o fecha direto em EM_ANDAMENTO")
        void jobFechaEmAndamento() {
            Turno t = publicar(2, LocalDateTime.now().plusMinutes(20));
            turnos.aceitar(t.getId(), ricardo.getId());
            checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);
            moverInicio(t, LocalDateTime.now().minusMinutes(1));

            expiracao.expirarTurnosNaoPreenchidos();

            assertThat(turnoRepo.findById(t.getId()).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.EM_ANDAMENTO);
        }
    }

    // ── presença na lista de inscritos ──────────────────────────────────────

    @Test
    @DisplayName("o lojista vê a chegada de cada um; o colega de vaga não vê a do outro")
    void presencaNosInscritos() {
        Turno t = publicar(2, LocalDateTime.now().plusMinutes(20));
        turnos.aceitar(t.getId(), ricardo.getId());
        turnos.aceitar(t.getId(), lucas.getId());
        checkins.checkin(t.getId(), ricardo.getId(), LAT, LNG);

        Map<String, Object> doRicardoParaLoja = doInscrito(consultas.listarInscritos(t.getId(), loja.getId()), ricardo);
        assertThat(doRicardoParaLoja.get("checkinEm")).isNotNull();
        assertThat(doRicardoParaLoja.get("minutosDoInicio")).isNotNull();

        Map<String, Object> doRicardoParaLucas = doInscrito(consultas.listarInscritos(t.getId(), lucas.getId()), ricardo);
        assertThat(doRicardoParaLucas).doesNotContainKey("checkinEm");

        Map<String, Object> doRicardoParaEle = doInscrito(consultas.listarInscritos(t.getId(), ricardo.getId()), ricardo);
        assertThat(doRicardoParaEle.get("checkinEm")).isNotNull();
    }

    // ── pontualidade ────────────────────────────────────────────────────────

    @Nested
    @DisplayName("pontualidade: check-ins até 10 min após o início, 90 dias")
    class Pontualidade {

        @Test
        @DisplayName("sem check-in é \"sem histórico\" — nulo, nunca 100%")
        void semHistorico() {
            Reputacao.Pontualidade p = reputacao.pontualidade(ricardo.getId());
            assertThat(p.percentual()).isNull();
            assertThat(p.checkins()).isZero();
        }

        @Test
        @DisplayName("antes, 10 min depois (ainda pontual) e 12 min depois: 67%")
        void percentual() {
            chegada(ricardo, LocalDateTime.now().minusDays(3), -5);
            chegada(ricardo, LocalDateTime.now().minusDays(10), 10);
            chegada(ricardo, LocalDateTime.now().minusDays(20), 12);

            Reputacao.Pontualidade p = reputacao.pontualidade(ricardo.getId());
            assertThat(p.checkins()).isEqualTo(3);
            assertThat(p.percentual()).isEqualTo(67);
        }

        @Test
        @DisplayName("check-in de turno com mais de 90 dias não entra")
        void janela() {
            chegada(ricardo, LocalDateTime.now().minusDays(95), 30);
            chegada(ricardo, LocalDateTime.now().minusDays(5), 0);

            Reputacao.Pontualidade p = reputacao.pontualidade(ricardo.getId());
            assertThat(p.checkins()).isEqualTo(1);
            assertThat(p.percentual()).isEqualTo(100);
        }
    }

    // ── apoio ───────────────────────────────────────────────────────────────

    /** Turno de 1 vaga no ponto do Água Verde, aceito por [quem], começando em [inicio]. */
    private Turno turnoAceito(Usuario quem, LocalDateTime inicio) {
        Turno t = publicar(1, inicio);
        turnos.aceitar(t.getId(), quem.getId());
        return turnoRepo.findById(t.getId()).orElseThrow();
    }

    /** Publica pelo serviço (a RF04 exige 2h) e depois traz o início para [inicio]. */
    private Turno publicar(int vagas, LocalDateTime inicio) {
        Turno t = cenario.publicar(loja.getId(), "100.00", vagas);
        t.setLatitude(LAT);
        t.setLongitude(LNG);
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        return turnoRepo.save(t);
    }

    private void moverInicio(Turno t, LocalDateTime inicio) {
        Turno atual = turnoRepo.findById(t.getId()).orElseThrow();
        atual.setDataInicio(inicio);
        atual.setDataFim(inicio.plusHours(4));
        turnoRepo.save(atual);
    }

    /** Um check-in já feito, [minutos] depois do início de um turno em [inicio]. */
    private void chegada(Usuario quem, LocalDateTime inicio, int minutos) {
        Turno t = publicar(1, inicio);
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(t.getId());
        ins.setMotoboyId(quem.getId());
        ins.setStatus(StatusInscricao.FINALIZADO);
        ins.setCheckinEm(inicio.plusMinutes(minutos));
        inscricaoRepo.save(ins);
    }

    private TurnoInscricao inscricao(Turno t, Usuario quem) {
        return inscricaoRepo.findByTurnoIdAndMotoboyId(t.getId(), quem.getId()).orElseThrow();
    }

    private List<Notificacao> avisos(Usuario u, String tipo) {
        return notificacaoRepo.findAll().stream()
                .filter(n -> n.getUsuarioId().equals(u.getId()) && tipo.equals(n.getTipo()))
                .toList();
    }

    private static Map<String, Object> doInscrito(List<Map<String, Object>> lista, Usuario u) {
        return lista.stream()
                .filter(m -> u.getId().equals(m.get("motoboyId")))
                .findFirst()
                .orElseThrow();
    }
}
