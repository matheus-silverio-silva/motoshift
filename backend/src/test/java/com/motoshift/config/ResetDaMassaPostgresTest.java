package com.motoshift.config;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.ledger.ConsistenciaService;
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
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Os dois modos de {@code MOTOSHIFT_SEED_RESET}, do runner do boot até o banco,
 * sobre PostgreSQL com Flyway e as chaves estrangeiras da V11 — o mesmo banco
 * que o Railway tem.
 *
 * <p>O runner é construído com o valor da variável, e a massa é o bean de
 * verdade: o que se testa aqui é exatamente o caminho de um deploy com a
 * variável definida.
 */
@SpringBootTest
@ActiveProfiles("test")
class ResetDaMassaPostgresTest {

    @DynamicPropertySource
    static void postgres(DynamicPropertyRegistry props) {
        String url = PostgresDeTeste.bancoNovo("reset_massa_pg");
        props.add("spring.datasource.url", () -> url);
        props.add("spring.datasource.username", () -> "postgres");
        props.add("spring.datasource.password", () -> "");
        props.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        props.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.PostgreSQLDialect");
        props.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        props.add("spring.flyway.enabled", () -> "true");
        props.add("spring.flyway.locations", () -> "classpath:db/migration");
    }

    @Autowired private MassaDemonstracao massa;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private JdbcTemplate jdbc;

    @Test
    @DisplayName("valor errado não faz nada: nem a massa, nem a conta real, nem o histórico do Flyway")
    void valorErradoNaoFazNada() {
        Usuario real = contaReal("Loja que fica", "loja@quefica.com.br", "lojista");
        Map<String, Long> antes = massa.contarTudo();
        Flyway flywayAntes = flyway();
        List<Long> idsAntes = jdbc.queryForList("SELECT id FROM usuarios ORDER BY id", Long.class);

        for (String valor : new String[] {"", "sim", "CONFIRMO", " confirmo", "confirmo-apagar",
                "apagar-tudo", "CONFIRMO-APAGAR-TUDO", "confirmo apagar tudo", "confirmo-apagar-tudo "}) {
            new ResetDaMassaNoBoot(massa, valor).run(null);
        }

        assertThat(massa.contarTudo()).isEqualTo(antes);
        assertThat(jdbc.queryForList("SELECT id FROM usuarios ORDER BY id", Long.class)).isEqualTo(idsAntes);
        assertThat(usuarioRepo.findById(real.getId())).isPresent();
        assertThat(flyway()).isEqualTo(flywayAntes);
    }

    @Test
    @DisplayName("confirmo: recria só a massa — a conta real e o turno dela ficam")
    void confirmoApagaSoAMassa() {
        Usuario loja = contaReal("Loja real", "loja@lojareal.com.br", "lojista");
        Turno proprio = turnoReal(loja);
        Flyway flywayAntes = flyway();

        new ResetDaMassaNoBoot(massa, "confirmo").run(null);

        assertThat(contasDaMassa()).isEqualTo(8);
        assertThat(usuarioRepo.findById(loja.getId())).isPresent();
        assertThat(turnoRepo.findById(proprio.getId())).isPresent();
        assertThat(flyway()).isEqualTo(flywayAntes);
        consistencia.verificarConsistencia(idsDaMassa()).exigirConsistente();
    }

    @Test
    @DisplayName("confirmo-apagar-tudo: só sobra a massa nova; schema e flyway_schema_history intactos")
    void confirmoApagarTudo() {
        Usuario loja = contaReal("Loja real", "outra@lojareal.com.br", "lojista");
        Usuario entregador = contaReal("Entregador real", "entregador@real.com.br", "motoboy");
        Turno proprio = turnoReal(loja);
        // Uma vaga do entregador real num turno da massa: a referência cruzada
        // que a ordem das FKs precisa respeitar.
        Long turnoDaMassa = jdbc.queryForObject(
                "SELECT t.id FROM turnos t JOIN usuarios u ON u.id = t.lojist_id "
              + "WHERE u.email = 'claudia@teste.com' AND t.status = 'aberto' LIMIT 1", Long.class);
        TurnoInscricao vaga = new TurnoInscricao();
        vaga.setTurnoId(turnoDaMassa);
        vaga.setMotoboyId(entregador.getId());
        vaga.setStatus(StatusInscricao.ACEITO);
        vaga = inscricaoRepo.save(vaga);
        Flyway flywayAntes = flyway();

        new ResetDaMassaNoBoot(massa, "confirmo-apagar-tudo").run(null);

        assertThat(usuarioRepo.findById(loja.getId())).isEmpty();
        assertThat(usuarioRepo.findById(entregador.getId())).isEmpty();
        assertThat(turnoRepo.findById(proprio.getId())).isEmpty();
        assertThat(inscricaoRepo.findById(vaga.getId())).isEmpty();
        // Toda conta que sobrou é da massa, e são as oito.
        assertThat(jdbc.queryForObject("SELECT count(*) FROM usuarios", Integer.class)).isEqualTo(8);
        assertThat(contasDaMassa()).isEqualTo(8);
        // Nada fora das contas da massa sobrou em tabela nenhuma de negócio.
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM transacoes WHERE usuario_id NOT IN (SELECT id FROM usuarios)",
                Integer.class)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM turnos WHERE lojist_id NOT IN (SELECT id FROM usuarios)",
                Integer.class)).isZero();

        // O que o boot precisa para não reaplicar migração continua igual.
        assertThat(flyway()).isEqualTo(flywayAntes);
        assertThat(flywayAntes.versao()).isEqualTo("14");
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND NOT convalidated",
                Integer.class)).isZero();

        consistencia.verificarConsistencia(idsDaMassa()).exigirConsistente();
    }

    @Test
    @DisplayName("o reset total devolve antes, apagados e depois — o que vai para o log")
    void resetTotalContaAntesEDepois() {
        contaReal("Mais uma", "mais@uma.com.br", "motoboy");
        Map<String, Long> antes = massa.contarTudo();

        Map<String, long[]> resumo = massa.apagarTudoERecriar();

        assertThat(resumo.keySet()).containsExactly("notas_fiscais", "avaliacoes", "transacoes",
                "cobrancas", "turno_inscricoes", "notificacoes", "turnos", "carteiras", "usuarios");
        resumo.forEach((tabela, linha) -> {
            assertThat(linha[0]).as("antes de %s", tabela).isEqualTo(antes.get(tabela));
            assertThat(linha[1]).as("apagados de %s", tabela).isEqualTo(antes.get(tabela));
        });
        assertThat(resumo.get("usuarios")[2]).isEqualTo(8);
        assertThat(massa.contarTudo()).containsEntry("usuarios", 8L);
    }

    // ── Apoio ────────────────────────────────────────────────────────────────

    /** O que o Flyway lê no boot: quantas migrações, a última, e se todas deram certo. */
    private record Flyway(int linhas, String versao, int falhas) {}

    private Flyway flyway() {
        return new Flyway(
                jdbc.queryForObject("SELECT count(*) FROM flyway_schema_history", Integer.class),
                jdbc.queryForObject("SELECT max(version::int)::text FROM flyway_schema_history WHERE success",
                        String.class),
                jdbc.queryForObject("SELECT count(*) FROM flyway_schema_history WHERE NOT success",
                        Integer.class));
    }

    private int contasDaMassa() {
        return jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email LIKE '%" + MassaDemonstracao.SUFIXO_EMAIL + "'",
                Integer.class);
    }

    private List<Long> idsDaMassa() {
        return jdbc.queryForList(
                "SELECT id FROM usuarios WHERE email LIKE '%" + MassaDemonstracao.SUFIXO_EMAIL + "'",
                Long.class);
    }

    private Turno turnoReal(Usuario loja) {
        Turno t = new Turno();
        t.setLojistId(loja.getId());
        t.setTitulo("Turno da loja real");
        t.setDataInicio(LocalDateTime.now().plusDays(1));
        t.setDataFim(LocalDateTime.now().plusDays(1).plusHours(4));
        t.setValorEstimado(new BigDecimal("90.00"));
        return turnoRepo.save(t);
    }

    private Usuario contaReal(String nome, String email, String tipo) {
        Usuario u = new Usuario();
        u.setNome(nome);
        // Sufixo único: os métodos compartilham o banco do contexto.
        u.setEmail(email.replace("@", "+" + System.nanoTime() + "@"));
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        u.setSenha("$2a$10$naoimportaparaestetesteaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        return usuarioRepo.save(u);
    }
}
