package com.motoshift.security;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * A janela deslizante sozinha, com o relógio na mão do teste (SCRUM-36).
 *
 * <p>Nada de Spring aqui: é a conta que decide o 429, e conta se testa sem
 * subir contexto. O instante vem por parâmetro, então "uma hora depois" é uma
 * soma, não uma espera.
 */
class JanelaDeslizanteTest {

    private static final long MINUTO = 60_000;
    private static final long HORA = 60 * MINUTO;

    @Test
    @DisplayName("deixa passar até o limite e recusa a seguinte, dizendo quanto falta")
    void ateOLimite() {
        JanelaDeslizante janela = new JanelaDeslizante(3, Duration.ofHours(1));
        long t0 = 1_000_000;

        assertThat(janela.registrar("ana", t0).permitido()).isTrue();
        assertThat(janela.registrar("ana", t0 + 10 * MINUTO).permitido()).isTrue();
        assertThat(janela.registrar("ana", t0 + 20 * MINUTO).permitido()).isTrue();

        JanelaDeslizante.Decisao quarta = janela.registrar("ana", t0 + 30 * MINUTO);
        assertThat(quarta.permitido()).isFalse();
        // A vaga abre quando a primeira (t0) completar uma hora: faltam 30 min.
        assertThat(quarta.esperarSegundos()).isEqualTo(30 * 60);
    }

    @Test
    @DisplayName("é deslizante: a vaga volta quando a requisição mais antiga sai da janela, não na hora cheia")
    void deslizante() {
        JanelaDeslizante janela = new JanelaDeslizante(2, Duration.ofHours(1));
        long t0 = 5 * HORA;

        janela.registrar("ana", t0);
        janela.registrar("ana", t0 + 50 * MINUTO);

        // 59 min depois da primeira: as duas ainda estão na janela.
        assertThat(janela.registrar("ana", t0 + 59 * MINUTO).permitido()).isFalse();
        // 60 min depois da primeira: ela saiu, cabe uma.
        assertThat(janela.registrar("ana", t0 + 60 * MINUTO).permitido()).isTrue();
        // E só uma: a de t0+50 e a de t0+60 enchem a janela de novo — um
        // contador que zerasse na virada da hora deixaria passar outra.
        JanelaDeslizante.Decisao seguinte = janela.registrar("ana", t0 + 61 * MINUTO);
        assertThat(seguinte.permitido()).isFalse();
        assertThat(seguinte.esperarSegundos()).isEqualTo(49 * 60);
    }

    @Test
    @DisplayName("requisição recusada não conta: insistir durante o bloqueio não adia a liberação")
    void recusadaNaoConta() {
        JanelaDeslizante janela = new JanelaDeslizante(1, Duration.ofMinutes(10));
        long t0 = 0;
        janela.registrar("ip", t0);

        for (int minuto = 1; minuto < 10; minuto++) {
            assertThat(janela.registrar("ip", t0 + minuto * MINUTO).permitido()).isFalse();
        }
        assertThat(janela.registrar("ip", t0 + 10 * MINUTO).permitido()).isTrue();
    }

    @Test
    @DisplayName("cada chave tem a sua janela")
    void chavesIndependentes() {
        JanelaDeslizante janela = new JanelaDeslizante(1, Duration.ofHours(1));

        assertThat(janela.registrar("ana", 0).permitido()).isTrue();
        assertThat(janela.registrar("ana", 1).permitido()).isFalse();
        assertThat(janela.registrar("beto", 1).permitido()).isTrue();
    }

    @Test
    @DisplayName("o tempo de espera nunca é zero numa recusa: Retry-After: 0 seria um convite a repetir já")
    void esperaMinimaDeUmSegundo() {
        JanelaDeslizante janela = new JanelaDeslizante(1, Duration.ofSeconds(10));
        janela.registrar("ip", 0);

        JanelaDeslizante.Decisao quase = janela.registrar("ip", 9_999);
        assertThat(quase.permitido()).isFalse();
        assertThat(quase.esperarSegundos()).isEqualTo(1);
    }

    @Test
    @DisplayName("a faxina joga fora as chaves vencidas e mantém as que ainda contam")
    void faxina() {
        JanelaDeslizante janela = new JanelaDeslizante(5, Duration.ofMinutes(10));
        for (int i = 0; i < 100; i++) {
            janela.registrar("antigo-" + i, 0);
        }
        janela.registrar("recente", 9 * MINUTO);
        assertThat(janela.chavesGuardadas()).isEqualTo(101);

        janela.faxina(11 * MINUTO);

        assertThat(janela.chavesGuardadas()).isEqualTo(1);
        // A contagem da que ficou continua valendo.
        for (int i = 0; i < 4; i++) {
            assertThat(janela.registrar("recente", 11 * MINUTO).permitido()).isTrue();
        }
        assertThat(janela.registrar("recente", 11 * MINUTO).permitido()).isFalse();
    }

    @Test
    @DisplayName("com requisições simultâneas da mesma chave, passam exatamente as do limite")
    void simultaneas() throws Exception {
        int limite = 10;
        int tentativas = 200;
        JanelaDeslizante janela = new JanelaDeslizante(limite, Duration.ofHours(1));
        AtomicInteger aceitas = new AtomicInteger();
        CountDownLatch largada = new CountDownLatch(1);
        ExecutorService pool = Executors.newFixedThreadPool(16);
        try {
            for (int i = 0; i < tentativas; i++) {
                pool.submit(() -> {
                    largada.await();
                    if (janela.registrar("mesma", 1_000).permitido()) aceitas.incrementAndGet();
                    return null;
                });
            }
            largada.countDown();
            pool.shutdown();
            assertThat(pool.awaitTermination(20, TimeUnit.SECONDS)).isTrue();
        } finally {
            pool.shutdownNow();
        }

        assertThat(aceitas.get()).isEqualTo(limite);
    }

    @Test
    @DisplayName("limite ou janela que não são positivos não constroem")
    void parametrosInvalidos() {
        assertThatThrownBy(() -> new JanelaDeslizante(0, Duration.ofHours(1)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new JanelaDeslizante(10, Duration.ZERO))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
