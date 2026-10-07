package com.motoshift.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.io.support.ResourcePropertySource;

import java.io.IOException;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O que os dois arquivos de propriedades prometem sobre variáveis de ambiente
 * (SCRUM-36) — lidos direto, sem subir o contexto.
 *
 * <p>O modelo da IA era um texto fixo nos dois perfis: trocar de modelo pedia
 * um commit e um deploy. Agora é {@code ANTHROPIC_MODEL}, com o mesmo padrão
 * de antes para quem não define a variável.
 */
class PropriedadesDeConfiguracaoTest {

    private static StandardEnvironment ambiente(String arquivo, Map<String, Object> variaveis)
            throws IOException {
        StandardEnvironment env = new StandardEnvironment();
        // Só o arquivo e as variáveis do teste: o ambiente da máquina que roda
        // a suíte não pode decidir o resultado.
        env.getPropertySources().remove(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME);
        env.getPropertySources().remove(StandardEnvironment.SYSTEM_PROPERTIES_PROPERTY_SOURCE_NAME);
        env.getPropertySources().addFirst(new ResourcePropertySource("classpath:" + arquivo));
        env.getPropertySources().addFirst(new MapPropertySource("variaveis-do-teste", variaveis));
        return env;
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"application.properties", "application-prod.properties"})
    @DisplayName("sem ANTHROPIC_MODEL, o modelo é o padrão de sempre")
    void modeloPadrao(String arquivo) throws IOException {
        assertThat(ambiente(arquivo, Map.of()).getProperty("anthropic.model"))
                .isEqualTo("claude-sonnet-4-20250514");
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"application.properties", "application-prod.properties"})
    @DisplayName("com ANTHROPIC_MODEL, o modelo é o da variável — sem recompilar")
    void modeloPelaVariavel(String arquivo) throws IOException {
        assertThat(ambiente(arquivo, Map.of("ANTHROPIC_MODEL", "modelo-de-teste"))
                .getProperty("anthropic.model")).isEqualTo("modelo-de-teste");
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"application.properties", "application-prod.properties"})
    @DisplayName("o limite de requisições nasce ligado e tem uma variável para desligar")
    void limiteLigadoPorPadrao(String arquivo) throws IOException {
        assertThat(ambiente(arquivo, Map.of()).getProperty("motoshift.limite.habilitado"))
                .isEqualTo("true");
        assertThat(ambiente(arquivo, Map.of("MOTOSHIFT_LIMITE_HABILITADO", "false"))
                .getProperty("motoshift.limite.habilitado")).isEqualTo("false");
    }

    @Test
    @DisplayName("o cabeçalho do IP: vazio em dev (não há proxy em que confiar), X-Forwarded-For em produção")
    void cabecalhoDoIpPorPerfil() throws IOException {
        assertThat(ambiente("application.properties", Map.of())
                .getProperty("motoshift.limite.cabecalho-do-ip")).isEmpty();
        assertThat(ambiente("application-prod.properties", Map.of())
                .getProperty("motoshift.limite.cabecalho-do-ip")).isEqualTo("X-Forwarded-For");
        assertThat(ambiente("application-prod.properties",
                Map.of("MOTOSHIFT_LIMITE_CABECALHO_IP", "X-Real-IP"))
                .getProperty("motoshift.limite.cabecalho-do-ip")).isEqualTo("X-Real-IP");
    }

    @Test
    @DisplayName("proxies confiáveis: 0 em dev, 1 em produção (Render), e uma variável para outra hospedagem (SCRUM-48)")
    void proxiesConfiaveisPorPerfil() throws IOException {
        assertThat(ambiente("application.properties", Map.of())
                .getProperty("motoshift.limite.proxies-confiaveis")).isEqualTo("0");
        assertThat(ambiente("application-prod.properties", Map.of())
                .getProperty("motoshift.limite.proxies-confiaveis")).isEqualTo("1");
        assertThat(ambiente("application-prod.properties",
                Map.of("MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS", "0"))
                .getProperty("motoshift.limite.proxies-confiaveis")).isEqualTo("0");
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"application.properties", "application-prod.properties"})
    @DisplayName("a versão do /api/status: o commit do Render, MOTOSHIFT_VERSAO por cima, vazio sem nenhum dos dois")
    void versaoNoAr(String arquivo) throws IOException {
        assertThat(ambiente(arquivo, Map.of()).getProperty("motoshift.versao")).isEmpty();
        assertThat(ambiente(arquivo, Map.of("RENDER_GIT_COMMIT", "ce600ba"))
                .getProperty("motoshift.versao")).isEqualTo("ce600ba");
        assertThat(ambiente(arquivo, Map.of("RENDER_GIT_COMMIT", "ce600ba", "MOTOSHIFT_VERSAO", "v2"))
                .getProperty("motoshift.versao")).isEqualTo("v2");
    }

    @Test
    @DisplayName("o Swagger só é desligado no arquivo de produção")
    void swaggerSoEmProd() throws IOException {
        StandardEnvironment dev = ambiente("application.properties", Map.of());
        assertThat(dev.getProperty("springdoc.api-docs.enabled")).isNull();
        assertThat(dev.getProperty("springdoc.swagger-ui.enabled")).isNull();

        StandardEnvironment prod = ambiente("application-prod.properties", Map.of());
        assertThat(prod.getProperty("springdoc.api-docs.enabled")).isEqualTo("false");
        assertThat(prod.getProperty("springdoc.swagger-ui.enabled")).isEqualTo("false");
    }
}
