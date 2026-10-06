package com.motoshift;

import com.motoshift.config.DataInitializer;
import com.motoshift.controller.ConsistenciaController;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.support.PostgresDeTeste;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * O boot de PRODUÇÃO: perfil {@code prod}, PostgreSQL, Flyway e as variáveis
 * que o Railway injeta.
 *
 * <p>Nenhum teste subia o contexto com o perfil de produção — tudo o que só
 * muda lá (o que deixa de existir, o que passa a ser obrigatório) era
 * conferido lendo o arquivo de propriedades. Aqui o
 * {@code application-prod.properties} é carregado de verdade: as variáveis de
 * ambiente entram como propriedades, do jeito que o Railway as entrega.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("prod")
class PerfilDeProducaoTest {

    @DynamicPropertySource
    static void ambienteDoRailway(DynamicPropertyRegistry props) {
        String url = PostgresDeTeste.bancoNovo("perfil_prod");
        // spring.datasource.url do perfil é montada de PGHOST/PGPORT/PGDATABASE;
        // aqui vai a URL inteira do PostgreSQL embarcado.
        props.add("spring.datasource.url", () -> url);
        props.add("PGUSER", () -> "postgres");
        props.add("PGPASSWORD", () -> "");
        // As quatro variáveis sem default: sem elas o boot de produção falha,
        // de propósito.
        props.add("JWT_SECRET", () -> "segredo-de-teste-com-mais-de-32-caracteres-123456");
        props.add("MOTOSHIFT_CORS_ORIGINS", () -> "https://motoshift.example");
        props.add("MOTOSHIFT_FISCAL_CHAVE", () -> "chave-fiscal-de-teste");
        props.add("ANTHROPIC_API_KEY", () -> "sk-ant-teste");
        // Os jobs ficam ligados, como no Railway: num banco vazio eles rodam
        // e não encontram nada.
    }

    @Autowired private ApplicationContext contexto;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private MockMvc mvc;

    @Test
    @DisplayName("em produção a conferência do ledger não é rota: o controller nem é instanciado")
    void consistenciaNaoExisteEmProd() {
        assertThat(contexto.getBeansOfType(ConsistenciaController.class)).isEmpty();
        // O serviço fica: o reset da massa confere o ledger por ele.
        assertThat(contexto.getBeansOfType(ConsistenciaService.class)).hasSize(1);
    }

    @Test
    @DisplayName("em produção o boot não semeia nada: sem DataInitializer, e o banco sobe vazio")
    void semMassaEmProd() {
        assertThat(contexto.getBeansOfType(DataInitializer.class)).isEmpty();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM usuarios", Integer.class)).isZero();
    }

    // ── SCRUM-36: configuração de produção ────────────────────────────────

    @Test
    @DisplayName("em produção o Swagger está desligado: os beans do springdoc não existem")
    void swaggerDesligadoEmProd() {
        assertThat(contexto.getEnvironment().getProperty("springdoc.api-docs.enabled")).isEqualTo("false");
        assertThat(contexto.getEnvironment().getProperty("springdoc.swagger-ui.enabled")).isEqualTo("false");
        // Não é só a rota que deixa de ser pública: quem serve o JSON da API
        // e a página do Swagger nem é montado. (O OpenApiConfig do projeto,
        // que só guarda título e versão, continua — sem quem o publique.)
        assertThat(contexto.getBeansOfType(org.springdoc.webmvc.api.OpenApiWebMvcResource.class)).isEmpty();
        assertThat(contexto.getBeansOfType(org.springdoc.webmvc.ui.SwaggerWelcomeWebMvc.class)).isEmpty();
    }

    @Test
    @DisplayName("em produção as rotas do Swagger deixam de ser públicas: sem token, 401 — e não um 404 que confirma o que havia ali")
    void rotasDoSwaggerDeixamDeSerPublicas() throws Exception {
        for (String rota : new String[] {
                "/v3/api-docs", "/v3/api-docs/swagger-config", "/swagger-ui.html", "/swagger-ui/index.html"}) {
            mvc.perform(get(rota))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.codigo").value("nao_autenticado"));
        }
        // As que são públicas de verdade continuam: o healthcheck do Railway
        // depende disso.
        mvc.perform(get("/actuator/health")).andExpect(status().isOk());
    }

    @Test
    @DisplayName("em produção o modelo da IA é o padrão quando ANTHROPIC_MODEL não vem, e o limite lê o IP do X-Forwarded-For")
    void padroesDeProducao() {
        assertThat(contexto.getEnvironment().getProperty("anthropic.model"))
                .isEqualTo("claude-sonnet-4-20250514");
        assertThat(contexto.getEnvironment().getProperty("motoshift.limite.habilitado")).isEqualTo("true");
        assertThat(contexto.getEnvironment().getProperty("motoshift.limite.cabecalho-do-ip"))
                .isEqualTo("X-Forwarded-For");
    }
}
