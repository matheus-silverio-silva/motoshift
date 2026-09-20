package com.motoshift.service;

import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A janela do job que cobra a finalização.
 *
 * Nada tira um turno de ACEITO a não ser um humano finalizar, então "todo turno
 * com fim no passado" era um conjunto que só crescia e era reprocessado a cada
 * 5 minutos, para sempre. A notificação não se repetia (criarUnica), mas o
 * trabalho sim.
 */
@SpringBootTest
@ActiveProfiles("test")
class TurnoExpiracaoServiceTest {

    private static final Long LOJISTA = 960_001L;

    @Autowired private TurnoExpiracaoService job;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;

    @Test
    @DisplayName("cobra o turno que venceu ontem e ignora o que venceu ha meses")
    void cobrancaTemJanela() {
        Turno recente = vencido(LocalDateTime.now().minusDays(1));
        Turno antigo  = vencido(LocalDateTime.now().minusDays(60));

        job.cobrarFinalizacaoPendente();

        List<Long> cobrados = notificacaoRepo
                .findTop50ByUsuarioIdOrderByCriadoEmDesc(LOJISTA).stream()
                .filter(n -> "turno_pendente_finalizacao".equals(n.getTipo()))
                .map(Notificacao::getReferenciaId)
                .toList();

        assertThat(cobrados).contains(recente.getId());
        assertThat(cobrados).doesNotContain(antigo.getId());
    }

    private Turno vencido(LocalDateTime fim) {
        Turno t = new Turno();
        t.setLojistId(LOJISTA);
        t.setMotoboyId(960_002L);
        t.setTitulo("Turno vencido em " + fim);
        t.setDataInicio(fim.minusHours(4));
        t.setDataFim(fim);
        t.setValorEstimado(new BigDecimal("100.00"));
        t.setStatus(StatusTurno.ACEITO);
        return turnoRepo.save(t);
    }
}
