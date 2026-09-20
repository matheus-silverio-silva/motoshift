package com.motoshift.config.migracao;

import org.flywaydb.core.api.migration.BaseJavaMigration;
import org.flywaydb.core.api.migration.Context;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * V9 — Converte para BCrypt as senhas que ainda estao em texto puro.
 *
 * <p><b>Por que existe.</b> O banco do Railway tem contas gravadas antes do
 * BCrypt. Para nao tranca-las, o login tinha um segundo ramo que comparava a
 * senha em claro e a regravava com hash na primeira entrada — um comparador de
 * senha em texto puro vivo no caminho critico da autenticacao, e so para quem
 * nunca mais entrasse. Esta migracao faz a conversao de todas de uma vez; com
 * ela aplicada o ramo foi apagado do {@code AuthService}.
 *
 * <p><b>Por que em Java e nao em SQL.</b> O hash precisa ser o mesmo BCrypt que
 * o login confere. No SQL isso pediria a extensao pgcrypto — que o usuario do
 * banco pode nao ter permissao de criar, e uma migracao que falha derruba o
 * deploy. Aqui o hash sai da mesma biblioteca do app.
 *
 * <p><b>Por que e um bean.</b> O Spring Boot entrega ao Flyway toda
 * {@code JavaMigration} registrada no contexto. Registrar como bean, em vez de
 * deixar o Flyway varrer o pacote {@code db.migration}, evita depender da
 * varredura de classes dentro do jar executavel do Spring Boot.
 *
 * <p>O encoder e instanciado aqui, e nao injetado: uma migracao ja aplicada nao
 * pode mudar de comportamento se a configuracao do app mudar depois. A forca 10
 * e o padrao do {@code BCryptPasswordEncoder}, a mesma do SecurityConfig.
 *
 * <p>Idempotente: so toca linha cuja senha nao comeca com prefixo de BCrypt. A
 * senha continua sendo a mesma para a pessoa — so muda a forma de guardar.
 */
@Component
public class V9__Senhas_legadas_para_bcrypt extends BaseJavaMigration {

    private static final Logger log = LoggerFactory.getLogger(V9__Senhas_legadas_para_bcrypt.class);

    // $ e literal no LIKE do PostgreSQL; os prefixos sao as tres variantes de
    // BCrypt que o BCryptPasswordEncoder reconhece.
    private static final String SELECIONAR = """
            SELECT id, senha FROM usuarios
            WHERE senha NOT LIKE '$2a$%'
              AND senha NOT LIKE '$2b$%'
              AND senha NOT LIKE '$2y$%'
            """;

    private static final String ATUALIZAR = "UPDATE usuarios SET senha = ? WHERE id = ?";

    private final PasswordEncoder encoder = new BCryptPasswordEncoder();

    @Override
    public void migrate(Context context) throws Exception {
        Connection conexao = context.getConnection();

        Map<Long, String> emTextoPuro = new LinkedHashMap<>();
        try (PreparedStatement sel = conexao.prepareStatement(SELECIONAR);
             ResultSet rs = sel.executeQuery()) {
            while (rs.next()) {
                emTextoPuro.put(rs.getLong("id"), rs.getString("senha"));
            }
        }

        if (emTextoPuro.isEmpty()) {
            log.info("[V9] nenhuma senha em texto puro — nada a converter");
            return;
        }

        try (PreparedStatement upd = conexao.prepareStatement(ATUALIZAR)) {
            for (Map.Entry<Long, String> linha : emTextoPuro.entrySet()) {
                upd.setString(1, encoder.encode(linha.getValue()));
                upd.setLong(2, linha.getKey());
                upd.addBatch();
            }
            upd.executeBatch();
        }
        // So a contagem: nem id nem senha vao para o log.
        log.info("[V9] {} senha(s) em texto puro convertida(s) para BCrypt", emTextoPuro.size());
    }
}
