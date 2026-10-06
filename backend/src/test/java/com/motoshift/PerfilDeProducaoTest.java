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
}
