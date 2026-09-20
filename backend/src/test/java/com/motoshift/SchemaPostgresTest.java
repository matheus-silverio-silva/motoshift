package com.motoshift;

import com.motoshift.config.MassaDemonstracao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.support.PostgresDeTeste;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O contexto inteiro sobre PostgreSQL, com a configuracao de persistencia da
 * producao: Flyway ligado e {@code ddl-auto=validate}.
 *
 * Se uma entidade ganhar um campo sem a migracao correspondente — ou uma
 * migracao criar a coluna com tipo diferente —, o Hibernate recusa o schema e
 * este teste falha no CI, em vez de o boot falhar no Railway.
 *
 * O perfil continua "test", entao o gatilho de dev roda: a massa de
 * demonstracao inteira e gravada por cima das chaves estrangeiras da V11, o que
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
        assertThat(versao).isEqualTo("13");
    }

    @Test
    @DisplayName("a massa de demonstracao e gravada no PostgreSQL de producao")
    void massaGravada() {
        Integer contas = jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email LIKE '%@teste.com'", Integer.class);
        assertThat(contas).isEqualTo(8);
    }

    @Test
    @DisplayName("o reset apaga na ordem das FKs da V11, duas vezes, sem tocar em conta real")
    void resetRespeitaChavesEstrangeiras() {
        Usuario loja = contaReal("Loja real", "loja@lojareal.com.br", "lojista");
        Usuario entregador = contaReal("Entregador real", "entregador@real.com.br", "motoboy");

        Turno proprio = new Turno();
        proprio.setLojistId(loja.getId());
        proprio.setTitulo("Turno da loja real");
        proprio.setDataInicio(LocalDateTime.now().plusDays(1));
        proprio.setDataFim(LocalDateTime.now().plusDays(1).plusHours(4));
        proprio.setValorEstimado(new BigDecimal("90.00"));
        proprio = turnoRepo.save(proprio);

        // Uma vaga do entregador real num turno da massa: e a referencia que,
        // sem a limpeza na ordem certa, a fk_inscricao_turno recusaria.
        Long turnoDaMassa = jdbc.queryForObject(
                "SELECT t.id FROM turnos t JOIN usuarios u ON u.id = t.lojist_id "
              + "WHERE u.email = 'claudia@teste.com' AND t.status = 'aberto' LIMIT 1", Long.class);
        TurnoInscricao vaga = new TurnoInscricao();
        vaga.setTurnoId(turnoDaMassa);
        vaga.setMotoboyId(entregador.getId());
        vaga = inscricaoRepo.save(vaga);

        massa.resetar();
        massa.resetar();

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email LIKE '%@teste.com'", Integer.class))
                .isEqualTo(8);
        assertThat(usuarioRepo.findById(loja.getId())).isPresent();
        assertThat(usuarioRepo.findById(entregador.getId())).isPresent();
        assertThat(turnoRepo.findById(proprio.getId())).isPresent();
        assertThat(inscricaoRepo.findById(vaga.getId())).isEmpty();
        // E o reset nao deixou nenhuma FK para tras.
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND NOT convalidated",
                Integer.class)).isZero();
    }

    @Autowired private MassaDemonstracao massa;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;

    private Usuario contaReal(String nome, String email, String tipo) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(email);
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        u.setSenha("$2a$10$naoimportaparaestetesteaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        return usuarioRepo.save(u);
    }
}
