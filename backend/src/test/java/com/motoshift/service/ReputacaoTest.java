package com.motoshift.service;

import com.motoshift.dto.AvaliacaoRequest;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Reputação e média derivadas dos dados — nunca um número de enfeite.
 *
 * <p>O que estes testes prendem: score é só do entregador; entregador sem
 * histórico não mostra 5,0 ("Novo na plataforma"); o cancelamento tardio tira
 * 0,5 pela regra, e é o único jeito de o score mudar; e a média de avaliação
 * sai das avaliações, é nula enquanto não há nenhuma, e nunca é gravada à mão.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class ReputacaoTest {

    @Autowired private Reputacao reputacao;
    @Autowired private AuthService auth;
    @Autowired private DashboardService dashboard;
    @Autowired private TurnoService turnos;
    @Autowired private AvaliacaoService avaliacoes;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private CenarioFinanceiro cenario;

    private Long lojista;
    private Long entregador;

    @BeforeEach
    void contas() {
        lojista = cenario.conta("lojista", "Loja da Reputação", "11222333000144").getId();
        entregador = cenario.conta("motoboy", "Entregador Novo", "12345678900").getId();
    }

    @Test
    @DisplayName("conta nova não mostra 5,0: sem histórico o score é nulo, no perfil e no painel")
    void semHistorico_semScore() {
        assertThat(reputacao.temHistorico(entregador)).isFalse();
        assertThat(auth.buscarPorId(entregador).getScore()).isNull();
        assertThat(auth.buscarPerfilPublico(entregador).getScore()).isNull();

        Map<String, Object> painel = dashboard.doMotoboy(entregador);
        assertThat(painel.get("score")).isNull();
        assertThat(painel.get("novoNaPlataforma")).isEqualTo(true);
        assertThat(painel.get("mediaAvaliacao")).isNull();
    }

    @Test
    @DisplayName("o lojista não tem score — nem o 5,0 fixo que carregava")
    void lojistaSemScore() {
        cenario.turnoPago(lojista, "80.00", entregador);

        assertThat(auth.buscarPorId(lojista).getScore()).isNull();
        assertThat(auth.buscarPerfilPublico(lojista).getScore()).isNull();
    }

    @Test
    @DisplayName("com o primeiro turno concluído, o entregador passa a ter o score inicial")
    void primeiroTurno_scoreInicial() {
        cenario.turnoPago(lojista, "80.00", entregador);

        assertThat(auth.buscarPerfilPublico(entregador).getScore())
                .isEqualTo(Reputacao.SCORE_INICIAL);
        assertThat(dashboard.doMotoboy(entregador).get("novoNaPlataforma")).isEqualTo(false);
    }

    @Test
    @DisplayName("desistir da vaga a menos de 1h do início tira 0,5 — pela regra, no serviço")
    void desistenciaEmCimaDaHora_penaliza() {
        cenario.recarregar(lojista, "200.00");
        Turno t = cenario.publicar(lojista, "90.00", 1);
        cenario.inscrever(t, entregador);
        // O turno começa daqui a 30 minutos: desistir agora é em cima da hora.
        Turno emCimaDaHora = turnoRepo.findById(t.getId()).orElseThrow();
        LocalDateTime inicio = LocalDateTime.now().plusMinutes(30).truncatedTo(ChronoUnit.MINUTES);
        emCimaDaHora.setDataInicio(inicio);
        emCimaDaHora.setDataFim(inicio.plusHours(4));
        turnoRepo.save(emCimaDaHora);

        turnos.desistir(t.getId(), entregador);

        Usuario depois = usuarioRepo.findById(entregador).orElseThrow();
        assertThat(depois.getScore()).isEqualTo(4.5);
        // Sem nenhum turno concluído, e o turno nem foi cancelado: quem dá o
        // histórico é a própria desistência — o 4,5 precisa aparecer.
        assertThat(reputacao.temHistorico(entregador)).isTrue();
        assertThat(reputacao.scoreVisivel(depois)).isEqualTo(4.5);
        // V22: é a inscrição que guarda quem saiu e quando — o turno segue.
        Turno doTurno = turnoRepo.findById(t.getId()).orElseThrow();
        assertThat(doTurno.getCanceladoPorId()).isNull();
        assertThat(doTurno.getStatus()).isNotEqualTo(com.motoshift.entity.StatusTurno.CANCELADO);
    }

    @Test
    @DisplayName("a loja cancelar em cima da hora não custa nada ao entregador")
    void cancelamentoDaLoja_naoPenaliza() {
        cenario.recarregar(lojista, "200.00");
        Turno t = cenario.publicar(lojista, "90.00", 1);
        cenario.inscrever(t, entregador);
        Turno emCimaDaHora = turnoRepo.findById(t.getId()).orElseThrow();
        LocalDateTime inicio = LocalDateTime.now().plusMinutes(30).truncatedTo(ChronoUnit.MINUTES);
        emCimaDaHora.setDataInicio(inicio);
        emCimaDaHora.setDataFim(inicio.plusHours(4));
        turnoRepo.save(emCimaDaHora);

        turnos.cancelar(t.getId(), lojista);

        assertThat(usuarioRepo.findById(entregador).orElseThrow().getScore())
                .isEqualTo(Reputacao.SCORE_INICIAL);
        // V19: o turno guarda quem cancelou — a loja.
        Turno cancelado = turnoRepo.findById(t.getId()).orElseThrow();
        assertThat(cancelado.getCanceladoPorId()).isEqualTo(lojista);
        assertThat(cancelado.getCanceladoEm()).isNotNull();
    }

    @Test
    @DisplayName("a média sai das avaliações recebidas, pelo serviço, e é nula antes da primeira")
    void mediaDerivada() {
        Turno t1 = cenario.turnoPago(lojista, "80.00", entregador);
        Turno t2 = cenario.turnoPago(lojista, "80.00", entregador);
        assertThat(usuarioRepo.findById(entregador).orElseThrow().getMediaAvaliacao()).isNull();

        avaliacoes.avaliar(avaliacao(t1, entregador, 5), lojista);
        avaliacoes.avaliar(avaliacao(t2, entregador, 4), lojista);

        assertThat(usuarioRepo.findById(entregador).orElseThrow().getMediaAvaliacao()).isEqualTo(4.5);
        assertThat(avaliacoes.recebidasPor(entregador).get("mediaGeral")).isEqualTo(4.5);
    }

    private static AvaliacaoRequest avaliacao(Turno t, Long avaliado, int nota) {
        AvaliacaoRequest r = new AvaliacaoRequest();
        r.setTurnoId(t.getId());
        r.setAvaliadoId(avaliado);
        r.setNota(nota);
        r.setComentario("Pontual");
        return r;
    }
}
