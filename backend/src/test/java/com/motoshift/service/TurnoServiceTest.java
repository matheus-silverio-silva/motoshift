package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TurnoServiceTest {

    @Mock private TurnoRepository    turnoRepo;
    @Mock private UsuarioRepository  usuarioRepo;
    @Mock private TurnoInscricaoRepository inscricaoRepo;
    // Mesma classe de problema do inscricaoRepo: o P0 (SCRUM-20) passou a
    // notificar o lojista dentro de aceitar/finalizar/cancelar, e sem o mock
    // o @InjectMocks injeta null e o fluxo estoura antes da assercao.
    @Mock private NotificacaoService notificacoes;

    // O dinheiro saiu daqui: confirmar pagamento e creditar carteira agora sao
    // do PagamentoTurnoService. O TurnoService so o chama ao finalizar, entao
    // aqui ele entra mockado.
    @Mock private PagamentoTurnoService pagamentos;

    private TurnoService turnoService;

    @BeforeEach
    void setUp() {
        // Mapper e acesso entram de verdade, montados sobre os mesmos mocks: sao
        // finos, e mockar o mapper faria toda assercao sobre a resposta virar
        // null.
        turnoService = new TurnoService(
                turnoRepo, usuarioRepo, inscricaoRepo, notificacoes, pagamentos,
                new TurnoMapper(inscricaoRepo), new TurnoAcesso(turnoRepo, inscricaoRepo));
    }

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

        TurnoResponse resp = turnoService.criar(buildRequest(inicio, fim), 1L);

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
                .isThrownBy(() -> turnoService.criar(buildRequest(inicio, fim), 1L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));

        verify(turnoRepo, never()).save(any());
    }

    @Test
    @DisplayName("RF04 — criar turno com fim anterior ao início lança 400")
    void criar_fimAntesDoInicio_lanca400() {
        LocalDateTime inicio = LocalDateTime.now().plusHours(3);
        LocalDateTime fim    = inicio.minusHours(1);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.criar(buildRequest(inicio, fim), 1L))
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
                .isThrownBy(() -> turnoService.criar(buildRequest(inicio, fim), 1L))
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
        when(turnoRepo.save(any(Turno.class))).thenReturn(turno);

        TurnoResponse resp = turnoService.aceitar(1L, 2L);

        // Turno de vaga única: a primeira inscrição já lota e fecha o turno.
        assertThat(resp).isNotNull();
        assertThat(resp.getStatus()).isEqualTo("aceito");
        verify(inscricaoRepo).save(any(TurnoInscricao.class));
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

        // O conflito é detectado pelas inscrições ativas do motoboy, e não mais
        // por turnoRepo.findConflitos: com várias vagas o turno de origem pode
        // continuar "aberto" e escapava da query antiga.
        when(turnoRepo.findById(1L)).thenReturn(Optional.of(turno));
        when(inscricaoRepo.findByMotoboyIdAndStatus(2L, "aceito"))
                .thenReturn(List.of(buildInscricao(2L, 2L)));
        when(turnoRepo.findById(2L)).thenReturn(Optional.of(conflitante));

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.aceitar(1L, 2L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(409));

        verify(turnoRepo, never()).save(any());
        verify(inscricaoRepo, never()).save(any());
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

    @Test
    @DisplayName("RF05 — aceitar turno já lotado lança 409 mesmo com o turno ainda 'aberto'")
    void aceitar_vagasEsgotadas_lanca409() {
        Turno turno = buildTurno(1L,
                LocalDateTime.now().plusHours(3),
                LocalDateTime.now().plusHours(7),
                "aberto");
        turno.setVagas(2);

        when(turnoRepo.findById(1L)).thenReturn(Optional.of(turno));
        when(inscricaoRepo.countByTurnoIdAndStatus(1L, "aceito")).thenReturn(2L);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.aceitar(1L, 3L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(409));

        verify(inscricaoRepo, never()).save(any());
    }

    @Test
    @DisplayName("RF05 — motoboy que já aceitou o turno não pode aceitar de novo (409)")
    void aceitar_duplicado_lanca409() {
        Turno turno = buildTurno(1L,
                LocalDateTime.now().plusHours(3),
                LocalDateTime.now().plusHours(7),
                "aberto");

        when(turnoRepo.findById(1L)).thenReturn(Optional.of(turno));
        when(inscricaoRepo.existsByTurnoIdAndMotoboyIdAndStatus(1L, 2L, "aceito"))
                .thenReturn(true);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> turnoService.aceitar(1L, 2L))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(409));

        verify(inscricaoRepo, never()).save(any());
    }

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------

    private TurnoRequest buildRequest(LocalDateTime inicio, LocalDateTime fim) {
        TurnoRequest req = new TurnoRequest();
        // O id do dono nao vem mais daqui — o service recebe o lojista do token.
        req.setTitulo("Turno Teste");
        req.setDataInicio(inicio);
        req.setDataFim(fim);
        req.setValorEstimado(new BigDecimal("120.00"));
        return req;
    }

    private Turno buildTurno(long id, LocalDateTime inicio, LocalDateTime fim, String status) {
        Turno t = new Turno();
        // id é gerado pelo JPA (não tem setter); simula um turno já persistido.
        // temConflitoDeAgenda compara ids, então eles não podem ser nulos.
        ReflectionTestUtils.setField(t, "id", id);
        t.setLojistId(1L);
        t.setTitulo("Turno Teste");
        t.setDataInicio(inicio);
        t.setDataFim(fim);
        t.setValorEstimado(new BigDecimal("120.00"));
        t.setStatus(status);
        return t;
    }

    private TurnoInscricao buildInscricao(Long turnoId, Long motoboyId) {
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(turnoId);
        ins.setMotoboyId(motoboyId);
        ins.setStatus("aceito");
        return ins;
    }
}
