package com.motoshift;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.TimeZone;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * O sistema tem um fuso só, o de Curitiba (SCRUM-48).
 *
 * <p>O container do Render roda em UTC. Como o app manda as datas do turno em
 * hora local e o servidor as compara com {@code LocalDateTime.now()}, um
 * servidor em UTC punha todas as regras de horário três horas adiantadas. O
 * {@code MotoshiftApplication.main} agora põe a JVM no fuso do sistema antes
 * de o Spring subir; aqui se confere esse passo e que a própria suíte roda no
 * fuso de produção (o {@code argLine} do surefire, no pom.xml).
 */
class FusoHorarioTest {

    private final TimeZone original = TimeZone.getDefault();

    @AfterEach
    void devolverOFuso() {
        // Os testes abaixo trocam o fuso padrão da JVM, que é da suíte inteira.
        TimeZone.setDefault(original);
    }

    @Test
    @DisplayName("a suíte roda no fuso de produção — é o pom.xml que garante, inclusive no CI em UTC")
    void aSuiteRodaNoFusoDeProducao() {
        assertThat(TimeZone.getDefault().getID()).isEqualTo(MotoshiftApplication.FUSO_PADRAO);
        assertThat(ZoneId.systemDefault()).isEqualTo(ZoneId.of("America/Sao_Paulo"));
    }

    @Test
    @DisplayName("ao subir, a aplicação põe a JVM no fuso de Curitiba, mesmo num container em UTC")
    void aoSubir_fusoDeCuritiba() {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));

        ZoneId aplicado = MotoshiftApplication.aplicarFuso(null);

        assertThat(aplicado).isEqualTo(ZoneId.of("America/Sao_Paulo"));
        assertThat(TimeZone.getDefault().getID()).isEqualTo("America/Sao_Paulo");
        // O "agora" que as regras usam passa a ser o de Brasília: três horas
        // atrás do UTC, o ano inteiro (não há mais horário de verão).
        Duration diferenca = Duration.between(
                LocalDateTime.now(), LocalDateTime.now(ZoneId.of("UTC")));
        assertThat(diferenca.toMinutes()).isBetween(179L, 181L);
    }

    @Test
    @DisplayName("variável vazia vale o padrão; MOTOSHIFT_FUSO troca o fuso sem recompilar")
    void fusoPelaVariavel() {
        assertThat(MotoshiftApplication.aplicarFuso("  ").getId()).isEqualTo("America/Sao_Paulo");

        assertThat(MotoshiftApplication.aplicarFuso(" America/Manaus ").getId()).isEqualTo("America/Manaus");
        assertThat(TimeZone.getDefault().getID()).isEqualTo("America/Manaus");
    }

    @Test
    @DisplayName("fuso que não existe derruba o boot, em vez de virar GMT em silêncio")
    void fusoInvalido_derrubaOBoot() {
        assertThatThrownBy(() -> MotoshiftApplication.aplicarFuso("America/Curitiba"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("MOTOSHIFT_FUSO")
                .hasMessageContaining("America/Curitiba");
        // E não mexeu em nada.
        assertThat(TimeZone.getDefault()).isEqualTo(original);
    }
}
