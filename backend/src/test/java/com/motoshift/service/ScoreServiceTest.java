package com.motoshift.service;

import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.Desistencia;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * A análise de score quando a IA não responde.
 *
 * Todas as métricas — score, variação, classificação, eventos — são calculadas
 * aqui, sem depender da Anthropic. Mesmo assim o endpoint inteiro respondia 503
 * quando ela falhava: a tela ficava vazia por causa do complemento, não do
 * conteúdo.
 */
@ExtendWith(MockitoExtension.class)
class ScoreServiceTest {

    private static final Long MOTOBOY = 42L;

    @Mock private TurnoRepository turnoRepo;
    // A desistencia do entregador mora na inscricao (V22), nao no turno.
    @Mock private TurnoInscricaoRepository inscricaoRepo;
    @Mock private UsuarioRepository usuarioRepo;
    @Mock private AnthropicService anthropic;
    @Mock private Reputacao reputacao;

    @InjectMocks private ScoreService service;

    @Test
    @DisplayName("IA fora do ar: os numeros saem mesmo assim, com a analise marcada como indisponivel")
    void iaIndisponivel_devolveMetricas() {
        when(usuarioRepo.findById(MOTOBOY)).thenReturn(Optional.of(motoboy(4.0)));
        when(reputacao.scoreVisivel(any())).thenReturn(4.0);
        when(turnoRepo.findByMotoboyId(MOTOBOY)).thenReturn(List.of(
                turno(StatusTurno.FINALIZADO, LocalDateTime.now().minusDays(3))));
        when(inscricaoRepo.desistenciasDe(MOTOBOY)).thenReturn(List.of(
                desistenciaTardia(LocalDateTime.now().minusDays(2))));
        when(anthropic.chamarClaude(any(), any()))
                .thenThrow(new IllegalStateException("Erro na API Anthropic: HTTP 529"));

        Map<String, Object> resposta = service.analisar(MOTOBOY);

        assertThat(resposta.get("analise")).isNull();
        assertThat(resposta.get("analiseDisponivel")).isEqualTo(false);
        assertThat(resposta.get("scoreAtual")).isEqualTo(4.0);
        assertThat(resposta.get("classificacao")).isEqualTo("Bom");
        assertThat((List<?>) resposta.get("eventos")).hasSize(2);
    }

    @Test
    @DisplayName("scoreAnterior vai rotulado como estimativa — nao e medicao")
    void scoreAnterior_saiComoEstimado() {
        when(usuarioRepo.findById(MOTOBOY)).thenReturn(Optional.of(motoboy(4.0)));
        when(reputacao.scoreVisivel(any())).thenReturn(4.0);
        when(turnoRepo.findByMotoboyId(MOTOBOY)).thenReturn(List.of());
        when(inscricaoRepo.desistenciasDe(MOTOBOY)).thenReturn(List.of(
                desistenciaTardia(LocalDateTime.now().minusDays(1))));
        when(anthropic.chamarClaude(any(), any())).thenReturn("texto da analise");

        Map<String, Object> resposta = service.analisar(MOTOBOY);

        // 4.0 agora + 0.5 revertido da desistencia em cima da hora da janela.
        assertThat(resposta.get("scoreAnterior")).isEqualTo(4.5);
        assertThat(resposta.get("scoreAnteriorEstimado")).isEqualTo(true);
        assertThat(resposta.get("analise")).isEqualTo("texto da analise");
        assertThat(resposta.get("analiseDisponivel")).isEqualTo(true);
    }

    @Test
    @DisplayName("eventos: a desistencia com folga nao custa nada, a em cima da hora custa 0,5, e o turno que a loja cancelou nao e evento do entregador")
    @SuppressWarnings("unchecked")
    void eventos_saoAsDesistenciasDele() {
        when(usuarioRepo.findById(MOTOBOY)).thenReturn(Optional.of(motoboy(4.5)));
        when(reputacao.scoreVisivel(any())).thenReturn(4.5);
        // Ele era o entregador de um turno que a LOJA cancelou: nao conta.
        when(turnoRepo.findByMotoboyId(MOTOBOY)).thenReturn(List.of(
                turno(StatusTurno.CANCELADO, LocalDateTime.now().minusDays(4))));
        when(inscricaoRepo.desistenciasDe(MOTOBOY)).thenReturn(List.of(
                desistenciaComFolga(LocalDateTime.now().minusDays(5)),
                desistenciaTardia(LocalDateTime.now().minusDays(2))));
        when(anthropic.chamarClaude(any(), any())).thenReturn("texto da analise");

        Map<String, Object> resposta = service.analisar(MOTOBOY);

        List<Map<String, Object>> eventos = (List<Map<String, Object>>) resposta.get("eventos");
        assertThat(eventos).hasSize(2);
        // Do mais recente para o mais antigo.
        assertThat(eventos.get(0)).containsEntry("tipo", "cancelado_tardio").containsEntry("impacto", -0.5);
        assertThat(eventos.get(1)).containsEntry("tipo", "cancelado").containsEntry("impacto", 0.0);
        // So a desistencia em cima da hora entra na estimativa: 4,5 + 0,5.
        assertThat(resposta.get("scoreAnterior")).isEqualTo(5.0);
    }

    @Test
    @DisplayName("sem histórico não há score a analisar: 'Novo na plataforma', e a IA não é chamada")
    void semHistorico_novoNaPlataforma() {
        when(usuarioRepo.findById(MOTOBOY)).thenReturn(Optional.of(motoboy(5.0)));
        when(reputacao.scoreVisivel(any())).thenReturn(null);

        Map<String, Object> resposta = service.analisar(MOTOBOY);

        assertThat(resposta.get("scoreAtual")).isNull();
        assertThat(resposta.get("novoNaPlataforma")).isEqualTo(true);
        assertThat(resposta.get("classificacao")).isEqualTo("Novo na plataforma");
        org.mockito.Mockito.verifyNoInteractions(anthropic);
    }

    // ── Apoio ────────────────────────────────────────────────────────────────

    private Usuario motoboy(double score) {
        Usuario u = new Usuario();
        ReflectionTestUtils.setField(u, "id", MOTOBOY);
        u.setNome("Thiago Alves");
        u.setTipo("motoboy");
        u.setScore(score);
        return u;
    }

    private Turno turno(StatusTurno status, LocalDateTime inicio) {
        Turno t = new Turno();
        ReflectionTestUtils.setField(t, "id", 1L);
        t.setLojistId(1L);
        t.setMotoboyId(MOTOBOY);
        t.setTitulo("Turno");
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        t.setValorEstimado(new BigDecimal("100.00"));
        t.setStatus(status);
        return t;
    }

    /** Desistiu em cima da hora: 30 minutos antes do inicio. */
    private Desistencia desistenciaTardia(LocalDateTime inicio) {
        return new Desistencia(2L, "Turno de que desistiu", inicio, inicio.minusMinutes(30));
    }

    /** Desistiu com folga: na vespera. */
    private Desistencia desistenciaComFolga(LocalDateTime inicio) {
        return new Desistencia(3L, "Turno de que desistiu cedo", inicio, inicio.minusDays(1));
    }
}
