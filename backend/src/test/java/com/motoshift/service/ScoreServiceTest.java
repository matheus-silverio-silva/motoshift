package com.motoshift.service;

import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
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
    @Mock private UsuarioRepository usuarioRepo;
    @Mock private AnthropicService anthropic;

    @InjectMocks private ScoreService service;

    @Test
    @DisplayName("IA fora do ar: os numeros saem mesmo assim, com a analise marcada como indisponivel")
    void iaIndisponivel_devolveMetricas() {
        when(usuarioRepo.findById(MOTOBOY)).thenReturn(Optional.of(motoboy(4.0)));
        when(turnoRepo.findByMotoboyId(MOTOBOY)).thenReturn(List.of(
                turno(StatusTurno.FINALIZADO, LocalDateTime.now().minusDays(3)),
                canceladoTardio(LocalDateTime.now().minusDays(2))));
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
        when(turnoRepo.findByMotoboyId(MOTOBOY)).thenReturn(List.of(
                canceladoTardio(LocalDateTime.now().minusDays(1))));
        when(anthropic.chamarClaude(any(), any())).thenReturn("texto da analise");

        Map<String, Object> resposta = service.analisar(MOTOBOY);

        // 4.0 agora + 0.5 revertido do cancelamento tardio da janela.
        assertThat(resposta.get("scoreAnterior")).isEqualTo(4.5);
        assertThat(resposta.get("scoreAnteriorEstimado")).isEqualTo(true);
        assertThat(resposta.get("analise")).isEqualTo("texto da analise");
        assertThat(resposta.get("analiseDisponivel")).isEqualTo(true);
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

    /** Cancelado em cima da hora: atualizado depois de (inicio - 1h). */
    private Turno canceladoTardio(LocalDateTime inicio) {
        Turno t = turno(StatusTurno.CANCELADO, inicio);
        ReflectionTestUtils.setField(t, "atualizadoEm", inicio.minusMinutes(30));
        return t;
    }
}
