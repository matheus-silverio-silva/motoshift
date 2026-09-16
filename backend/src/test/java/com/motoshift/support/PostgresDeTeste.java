package com.motoshift.support;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * Um PostgreSQL de verdade para os testes que o H2 nao alcanca.
 *
 * As migracoes em db/migration sao SQL PostgreSQL (blocos DO $$, pg_constraint,
 * FOREIGN KEY ... NOT VALID) e o H2 nao as executa. Ate aqui a primeira vez que
 * elas rodavam de verdade era o boot de producao. O zonky baixa o binario do
 * PostgreSQL como artefato Maven e sobe um servidor local — sem Docker, igual
 * no Windows e no runner do CI.
 *
 * Um servidor por JVM, um banco por teste que precisa de banco limpo.
 */
public final class PostgresDeTeste {

    private static EmbeddedPostgres servidor;

    private PostgresDeTeste() {}

    public static synchronized EmbeddedPostgres servidor() {
        if (servidor == null) {
            try {
                servidor = EmbeddedPostgres.builder().start();
            } catch (IOException e) {
                throw new UncheckedIOException("PostgreSQL embarcado nao subiu", e);
            }
            // Sem isto o processo do postgres sobrevive ao fim do Maven.
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try {
                    servidor.close();
                } catch (IOException ignorado) {
                    // JVM ja esta saindo; nao ha o que fazer com o erro.
                }
            }));
        }
        return servidor;
    }

    /** Cria (ou recria) um banco vazio e devolve a URL JDBC dele. */
    public static String bancoNovo(String nome) {
        try (Connection c = servidor().getPostgresDatabase().getConnection();
             Statement s = c.createStatement()) {
            s.execute("DROP DATABASE IF EXISTS " + nome);
            s.execute("CREATE DATABASE " + nome);
        } catch (SQLException e) {
            throw new IllegalStateException("nao foi possivel criar o banco " + nome, e);
        }
        return servidor().getJdbcUrl("postgres", nome);
    }
}
