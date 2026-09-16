package com.motoshift.repository;

import com.motoshift.config.migracao.V9__Senhas_legadas_para_bcrypt;
import com.motoshift.support.PostgresDeTeste;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * As migracoes rodando num PostgreSQL de verdade.
 *
 * O cabecalho do ContextoESchemaTest registrava o buraco: "a primeira validacao
 * do SQL continua sendo o boot de producao". Aqui cada migracao roda antes do
 * deploy — inclusive as que dependem do estado que ja existe no banco, que e
 * onde migracao costuma quebrar.
 */
class MigracoesPostgresTest {

    @Test
    @DisplayName("todas as migracoes aplicam num banco vazio, na ordem")
    void bancoVazio() {
        String url = PostgresDeTeste.bancoNovo("mig_vazio");

        MigrateResult resultado = flyway(url, null).migrate();

        assertThat(resultado.success).isTrue();
        assertThat(resultado.targetSchemaVersion).isEqualTo(ultimaVersao());
    }

    @Test
    @DisplayName("V9 converte a senha em texto puro para BCrypt e nao mexe no que ja e hash")
    void v9_converteSenhaLegada() throws SQLException {
        String url = PostgresDeTeste.bancoNovo("mig_v9");
        flyway(url, "8").migrate();

        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();
        String hashExistente = encoder.encode("ja-era-hash");
        try (Connection c = conectar(url); Statement s = c.createStatement()) {
            s.execute(inserirUsuario("legado@railway.com", "senha123"));
            s.execute(inserirUsuario("novo@railway.com", hashExistente));
        }

        flyway(url, null).migrate();

        try (Connection c = conectar(url)) {
            String convertida = senhaDe(c, "legado@railway.com");
            // A pessoa continua entrando com a mesma senha — so a forma de
            // guardar mudou.
            assertThat(convertida).startsWith("$2a$");
            assertThat(encoder.matches("senha123", convertida)).isTrue();

            assertThat(senhaDe(c, "novo@railway.com")).isEqualTo(hashExistente);
        }
    }

    // ── Apoio ──────────────────────────────────────────────────────────────

    static Flyway flyway(String url, String alvo) {
        var cfg = Flyway.configure()
                .dataSource(url, "postgres", "")
                .locations("classpath:db/migration")
                // Em producao o Spring entrega a migracao Java ao Flyway por
                // ser um bean; fora do contexto, entra na mao.
                .javaMigrations(new V9__Senhas_legadas_para_bcrypt());
        if (alvo != null) cfg.target(alvo);
        return cfg.load();
    }

    static String ultimaVersao() {
        return "9";
    }

    static Connection conectar(String url) throws SQLException {
        return DriverManager.getConnection(url, "postgres", "");
    }

    static String inserirUsuario(String email, String senha) {
        return "INSERT INTO usuarios (nome, email, senha, telefone, tipo, score, criado_em) "
                + "VALUES ('Conta de teste', '" + email + "', '" + senha + "', '41999990000', "
                + "'motoboy', 5.0, now())";
    }

    private static String senhaDe(Connection c, String email) throws SQLException {
        try (Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT senha FROM usuarios WHERE email = '" + email + "'")) {
            rs.next();
            return rs.getString(1);
        }
    }
}
