package com.motoshift;

import com.motoshift.support.PostgresDeTeste;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O contexto inteiro sobre PostgreSQL, com a configuracao de persistencia da
 * producao: Flyway ligado e {@code ddl-auto=validate}.
 *
 * Se uma entidade ganhar um campo sem a migracao correspondente — ou uma
 * migracao criar a coluna com tipo diferente —, o Hibernate recusa o schema e
 * este teste falha no CI, em vez de o boot falhar no Railway.
 *
 * O perfil continua "test", entao o DataInitializer roda: a massa de
 * demonstracao inteira e gravada por cima das chaves estrangeiras da V10, o que
 * prova que o seed respeita a integridade que o banco de producao exige.
 */
@SpringBootTest
@ActiveProfiles("test")
class SchemaPostgresTest {

    @DynamicPropertySource
    static void postgres(DynamicPropertyRegistry props) {
        String url = PostgresDeTeste.bancoNovo("contexto_pg");
        props.add("spring.datasource.url", () -> url);
        props.add("spring.datasource.username", () -> "postgres");
        props.add("spring.datasource.password", () -> "");
        props.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        props.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.PostgreSQLDialect");
        props.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        props.add("spring.flyway.enabled", () -> "true");
        props.add("spring.flyway.locations", () -> "classpath:db/migration");
    }

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    @DisplayName("as entidades batem com o schema das migracoes (ddl-auto=validate)")
    void schemaValido() {
        // Chegar aqui ja e a assercao principal: o contexto so sobe se o
        // Hibernate aceitou o schema. O resto confere que foi o Flyway que o
        // criou — e nao um create-drop escondido.
        String versao = jdbc.queryForObject(
                "SELECT max(version::int)::text FROM flyway_schema_history WHERE success",
                String.class);
        assertThat(versao).isEqualTo("11");
    }

    @Test
    @DisplayName("a massa de demonstracao e gravada no PostgreSQL de producao")
    void massaGravada() {
        Integer contas = jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email LIKE '%@teste.com'", Integer.class);
        assertThat(contas).isEqualTo(8);
    }
}
