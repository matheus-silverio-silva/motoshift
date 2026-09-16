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
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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

    @Test
    @DisplayName("V10 unifica as palavras legadas, chaveia toda transacao e fecha o dominio")
    void v10_transacoes() throws SQLException {
        String url = PostgresDeTeste.bancoNovo("mig_v10");
        flyway(url, "9").migrate();

        try (Connection c = conectar(url); Statement s = c.createStatement()) {
            // Duas transacoes do mesmo turno para o mesmo entregador: o indice
            // unico so aceita a chave de pagamento em uma delas.
            s.execute(inserirTransacao(1, 10, "turno", "processado", null));
            s.execute(inserirTransacao(1, 10, "turno", "processado", null));
            s.execute(inserirTransacao(1, 11, "turno", "pendente", null));
            s.execute(inserirTransacao(1, null, "saque", "concluido", null));
        }

        flyway(url, null).migrate();

        try (Connection c = conectar(url); Statement s = c.createStatement()) {
            assertThat(contar(s, "SELECT count(*) FROM transacoes WHERE tipo = 'turno' OR status = 'processado'"))
                    .isZero();
            assertThat(contar(s, "SELECT count(*) FROM transacoes WHERE idempotency_key IS NULL"))
                    .isZero();

            try (ResultSet rs = s.executeQuery(
                    "SELECT idempotency_key FROM transacoes ORDER BY id")) {
                rs.next(); assertThat(rs.getString(1)).isEqualTo("pagamento_turno:10:1");
                rs.next(); assertThat(rs.getString(1)).startsWith("legado:");
                rs.next(); assertThat(rs.getString(1)).isEqualTo("pagamento_turno:11:1");
                rs.next(); assertThat(rs.getString(1)).startsWith("legado:");
            }

            // O banco passa a recusar o que o enum nao conhece.
            assertThatThrownBy(() -> s.execute(inserirTransacao(1, 12, "turno", "pendente", "x:1")))
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("ck_transacao_tipo");
            assertThatThrownBy(() -> s.execute(inserirTransacao(1, null, "saque", "pendente", null)))
                    .isInstanceOf(SQLException.class);
        }
    }

    @Test
    @DisplayName("V11: banco limpo sai com todas as FKs validadas")
    void v11_bancoLimpo() throws SQLException {
        String url = PostgresDeTeste.bancoNovo("mig_v11_limpo");
        flyway(url, null).migrate();

        try (Connection c = conectar(url); Statement s = c.createStatement()) {
            assertThat(contar(s, "SELECT count(*) FROM pg_constraint WHERE contype = 'f'"))
                    .isEqualTo(16);
            assertThat(contar(s, "SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND NOT convalidated"))
                    .isZero();
        }
    }

    @Test
    @DisplayName("V11: linha orfa antiga nao derruba o deploy, mas referencia quebrada nova e recusada")
    void v11_orfaNaoDerrubaODeploy() throws SQLException {
        String url = PostgresDeTeste.bancoNovo("mig_v11_orfa");
        flyway(url, "10").migrate();

        try (Connection c = conectar(url); Statement s = c.createStatement()) {
            // Transacao de um usuario que nao existe — o tipo de sobra que o
            // banco do Railway pode ter de antes das FKs.
            s.execute(inserirTransacao(999_999, null, "saque", "concluido", "orfa:1"));
        }

        MigrateResult resultado = flyway(url, null).migrate();
        assertThat(resultado.success).isTrue();

        try (Connection c = conectar(url); Statement s = c.createStatement()) {
            assertThat(validada(s, "fk_transacao_usuario")).isFalse();
            assertThat(validada(s, "fk_turno_lojista")).isTrue();

            // A FK NOT VALID ja vale para o que entra daqui para frente.
            assertThatThrownBy(() -> s.execute(inserirTransacao(424_242, null, "saque", "concluido", "orfa:2")))
                    .isInstanceOf(SQLException.class)
                    .extracting(e -> ((SQLException) e).getSQLState())
                    .isEqualTo("23503");
        }
    }

    // ── Apoio ──────────────────────────────────────────────────────────────

    static String inserirTransacao(long usuario, Integer turno, String tipo, String status, String chave) {
        return "INSERT INTO transacoes (usuario_id, turno_id, tipo, valor, status, idempotency_key, criado_em) "
                + "VALUES (" + usuario + ", " + turno + ", '" + tipo + "', 10.00, '" + status + "', "
                + (chave == null ? "NULL" : "'" + chave + "'") + ", now())";
    }

    private static long contar(Statement s, String sql) throws SQLException {
        try (ResultSet rs = s.executeQuery(sql)) {
            rs.next();
            return rs.getLong(1);
        }
    }

    private static boolean validada(Statement s, String restricao) throws SQLException {
        try (ResultSet rs = s.executeQuery(
                "SELECT convalidated FROM pg_constraint WHERE conname = '" + restricao + "'")) {
            rs.next();
            return rs.getBoolean(1);
        }
    }

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
        return "11";
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
