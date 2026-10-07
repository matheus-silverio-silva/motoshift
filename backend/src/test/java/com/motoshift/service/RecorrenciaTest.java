package com.motoshift.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Em que dias um lançamento recorrente acontece (RF13 / SCRUM-47).
 *
 * <p>Função pura: datas entram, datas saem. Os cantos estão aqui porque é
 * neles que uma recorrência mensal erra — o mês curto, o período que não
 * contém o dia e a recorrência que acaba no meio do período.
 */
class RecorrenciaTest {

    private static LocalDate dia(int ano, int mes, int dia) {
        return LocalDate.of(ano, mes, dia);
    }

    @Test
    @DisplayName("todo mês, no dia do mês da primeira data")
    void mensal() {
        assertThat(Recorrencia.ocorrencias(dia(2026, 1, 10), null, dia(2026, 1, 1), dia(2026, 4, 30)))
                .containsExactly(dia(2026, 1, 10), dia(2026, 2, 10), dia(2026, 3, 10), dia(2026, 4, 10));
    }

    @Test
    @DisplayName("dia 31 em fevereiro cai no último dia do mês — não some nem pula para março")
    void dia31EmFevereiro() {
        assertThat(Recorrencia.ocorrencias(dia(2026, 1, 31), null, dia(2026, 1, 1), dia(2026, 4, 30)))
                .containsExactly(dia(2026, 1, 31), dia(2026, 2, 28), dia(2026, 3, 31), dia(2026, 4, 30));
    }

    @Test
    @DisplayName("em ano bissexto, o dia 31 cai em 29 de fevereiro; o dia 29 volta a 28 no ano comum")
    void bissexto() {
        assertThat(Recorrencia.ocorrencias(dia(2028, 1, 31), null, dia(2028, 2, 1), dia(2028, 2, 29)))
                .containsExactly(dia(2028, 2, 29));
        assertThat(Recorrencia.ocorrencias(dia(2028, 2, 29), null, dia(2029, 2, 1), dia(2029, 2, 28)))
                .containsExactly(dia(2029, 2, 28));
    }

    @Test
    @DisplayName("período de meio mês: conta só se o dia cai dentro dele")
    void periodoDeMeioMes() {
        LocalDate todoDia20 = dia(2026, 1, 20);
        // 1 a 15: a conta está em vigor, mas ainda não venceu.
        assertThat(Recorrencia.vezes(todoDia20, null, dia(2026, 9, 1), dia(2026, 9, 15))).isZero();
        // 16 a 30: venceu.
        assertThat(Recorrencia.vezes(todoDia20, null, dia(2026, 9, 16), dia(2026, 9, 30))).isEqualTo(1);
        // Os extremos são inclusivos.
        assertThat(Recorrencia.vezes(todoDia20, null, dia(2026, 9, 20), dia(2026, 9, 20))).isEqualTo(1);
        assertThat(Recorrencia.vezes(todoDia20, null, dia(2026, 9, 21), dia(2026, 10, 19))).isZero();
    }

    @Test
    @DisplayName("recorrência que termina antes do fim do período para de contar no dia em que termina")
    void terminaAntesDoFimDoPeriodo() {
        LocalDate primeira = dia(2026, 1, 5);
        // Vale até 5 de março, inclusive: janeiro, fevereiro e março.
        assertThat(Recorrencia.ocorrencias(primeira, dia(2026, 3, 5), dia(2026, 1, 1), dia(2026, 6, 30)))
                .containsExactly(dia(2026, 1, 5), dia(2026, 2, 5), dia(2026, 3, 5));
        // Até 4 de março: a de março já não acontece.
        assertThat(Recorrencia.vezes(primeira, dia(2026, 3, 4), dia(2026, 1, 1), dia(2026, 6, 30)))
                .isEqualTo(2);
        // Terminou antes de o período começar.
        assertThat(Recorrencia.vezes(primeira, dia(2026, 3, 5), dia(2026, 4, 1), dia(2026, 6, 30)))
                .isZero();
    }

    @Test
    @DisplayName("não existe antes da primeira data, mesmo que o dia do mês caia no período")
    void naoComecaAntes() {
        LocalDate primeira = dia(2026, 3, 15);
        assertThat(Recorrencia.vezes(primeira, null, dia(2026, 1, 1), dia(2026, 2, 28))).isZero();
        assertThat(Recorrencia.ocorrencias(primeira, null, dia(2026, 1, 1), dia(2026, 4, 30)))
                .containsExactly(dia(2026, 3, 15), dia(2026, 4, 15));
    }

    @Test
    @DisplayName("atravessa a virada do ano")
    void viradaDoAno() {
        assertThat(Recorrencia.ocorrencias(dia(2025, 11, 30), null, dia(2025, 12, 1), dia(2026, 2, 28)))
                .containsExactly(dia(2025, 12, 30), dia(2026, 1, 30), dia(2026, 2, 28));
    }

    @Test
    @DisplayName("primeira ocorrência a partir de uma data: neste mês se o dia ainda não passou, no seguinte se já passou")
    void primeiraAPartirDe() {
        // O próprio dia conta.
        assertThat(Recorrencia.primeiraAPartirDe(20, dia(2026, 10, 1))).isEqualTo(dia(2026, 10, 20));
        assertThat(Recorrencia.primeiraAPartirDe(20, dia(2026, 10, 20))).isEqualTo(dia(2026, 10, 20));
        assertThat(Recorrencia.primeiraAPartirDe(20, dia(2026, 10, 21))).isEqualTo(dia(2026, 11, 20));
        // Mês curto: o último dia dele. E a virada do ano.
        assertThat(Recorrencia.primeiraAPartirDe(31, dia(2026, 2, 1))).isEqualTo(dia(2026, 2, 28));
        assertThat(Recorrencia.primeiraAPartirDe(31, dia(2026, 4, 30))).isEqualTo(dia(2026, 4, 30));
        assertThat(Recorrencia.primeiraAPartirDe(5, dia(2026, 12, 6))).isEqualTo(dia(2027, 1, 5));
    }

    @Test
    @DisplayName("período invertido ou datas ausentes não dão ocorrência nenhuma")
    void entradasSemSentido() {
        assertThat(Recorrencia.vezes(dia(2026, 1, 10), null, dia(2026, 3, 1), dia(2026, 2, 1))).isZero();
        assertThat(Recorrencia.vezes(null, null, dia(2026, 1, 1), dia(2026, 2, 1))).isZero();
        assertThat(Recorrencia.vezes(dia(2026, 1, 10), null, null, dia(2026, 2, 1))).isZero();
    }
}
