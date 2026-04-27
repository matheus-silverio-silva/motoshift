package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Turno;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TurnoServiceTest {

    @Mock private TurnoRepository    turnoRepo;
    @Mock private UsuarioRepository  usuarioRepo;
    @Mock private CarteiraRepository carteiraRepo;
    @Mock private TransacaoRepository transacaoRepo;

    @InjectMocks
    private TurnoService turnoService;

    // --------------------------------------------------------
    // RF04 — criar()
    // --------------------------------------------------------

    @Test
    @DisplayName("RF04 — criar turno com 3h de antecedência retorna TurnoResponse com status 'aberto'")
    void criar_antecedenciaSuficiente_retornaTurnoAberto() {
        LocalDateTime inicio = LocalDateTime.now().plusHours(3);
        LocalDateTime fim    = inicio.plusHours(4);

        Turno salvo = buildTurno(1L, inicio, fim, "aberto");
        when(turnoRepo.save(any(Turno.class))).thenReturn(salvo);

        TurnoResponse resp = turnoService.criar(buildRequest(inicio, fim));

        assertThat(resp).isNotNull();
        assertThat(resp.getStatus()).isEqualTo("aberto");
        verify(turnoRepo, times(1)).save(any(Turno.class));
    }

    @Test
    @DisplayName("RF04 — criar turno com 30min de antecedência lança 400")
    void criar_antecedenciaInsuficiente_lanca400() {
        LocalDateTime inicio = LocalDateTime.now().plusMinutes(30);
        LocalDateTime fim    = inicio.plusHours(2);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.criar(buildRequest(inicio, fim)))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));

        verify(turnoRepo, never()).save(any());
    }

    @Test
    @DisplayName("RF04 — criar turno com fim anterior ao início lança 400")
    void criar_fimAntesDoInicio_lanca400() {
        LocalDateTime inicio = LocalDateTime.now().plusHours(3);
        LocalDateTime fim    = inicio.minusHours(1);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.criar(buildRequest(inicio, fim)))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));

        verify(turnoRepo, never()).save(any());
    }

    @Test
    @DisplayName("RF04 — criar turno exatamente no limite (agora + 2h) lança 400 — boundary")
    void criar_exatamente2h_lanca400() {
        // isBefore(limiteMinimo) é falso, mas plusHours(2) é igual — não aceita igual
        LocalDateTime inicio = LocalDateTime.now().plusHours(2).minusSeconds(1);
        LocalDateTime fim    = inicio.plusHours(4);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.criar(buildRequest(inicio, fim)))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));
    }

    // --------------------------------------------------------
    // RF05 — aceitar()
    // --------------------------------------------------------

    @Test
    @DisplayName("RF05 — aceitar turno disponível sem conflito altera status para 'aceito'")
    void aceitar_semConflito_retornaTurnoAceito() {
        Turno turno = buildTurno(1L,
                LocalDateTime.now().plusHours(3),
                LocalDateTime.now().plusHours(7),
                "aberto");

        when(turnoRepo.findById(1L)).thenReturn(Optional.of(turno));
        when(turnoRepo.findConflitos(anyLong(), any(), any())).thenReturn(Collections.emptyList());
        when(turnoRepo.save(any(Turno.class))).thenReturn(turno);

        TurnoResponse resp = turnoService.aceitar(1L, 2L);

        assertThat(resp).isNotNull();
        assertThat(resp.getStatus()).isEqualTo("aceito");
        verify(turnoRepo).save(any(Turno.class));
    }

    @Test
    @DisplayName("RF05 — aceitar turno com conflito de horário lança 409")
    void aceitar_comConflito_lanca409() {
        Turno turno = buildTurno(1L,
                LocalDateTime.now().plusHours(3),
                LocalDateTime.now().plusHours(7),
                "aberto");

        Turno conflitante = buildTurno(2L,
                LocalDateTime.now().plusHours(2),
                LocalDateTime.now().plusHours(6),
                "aceito");

        when(turnoRepo.findById(1L)).thenReturn(Optional.of(turno));
        when(turnoRepo.findConflitos(anyLong(), any(), any())).thenReturn(List.of(conflitante));

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.aceitar(1L, 2L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(409));

        verify(turnoRepo, never()).save(any());
    }

    @Test
    @DisplayName("RF05 — aceitar turno inexistente lança 404")
    void aceitar_turnoNaoEncontrado_lanca404() {
        when(turnoRepo.findById(99L)).thenReturn(Optional.empty());

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.aceitar(99L, 2L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(404));
    }

    @Test
    @DisplayName("RF05 — aceitar turno que não está 'aberto' lança 409")
    void aceitar_turnoJaAceito_lanca409() {
        Turno turno = buildTurno(1L,
                LocalDateTime.now().plusHours(3),
                LocalDateTime.now().plusHours(7),
                "aceito");

        when(turnoRepo.findById(1L)).thenReturn(Optional.of(turno));

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.aceitar(1L, 2L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(409));

        verify(turnoRepo, never()).save(any());
    }

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------

    private TurnoRequest buildRequest(LocalDateTime inicio, LocalDateTime fim) {
        TurnoRequest req = new TurnoRequest();
        req.setLojistId(1L);
        req.setTitulo("Turno Teste");
        req.setDataInicio(inicio);
        req.setDataFim(fim);
        req.setValorEstimado(120.0);
        return req;
    }

    private Turno buildTurno(long ignoredId, LocalDateTime inicio, LocalDateTime fim, String status) {
        Turno t = new Turno();
        t.setLojistId(1L);
        t.setTitulo("Turno Teste");
        t.setDataInicio(inicio);
        t.setDataFim(fim);
        t.setValorEstimado(120.0);
        t.setStatus(status);
        return t;
    }
}
