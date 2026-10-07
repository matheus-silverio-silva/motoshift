package com.motoshift.controller;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** A "versao" do {@code /api/status}: commit, versão do pom ou "dev" (SCRUM-48). */
class StatusControllerTest {

    @Test
    @DisplayName("com o commit da hospedagem, a versão são os 7 primeiros caracteres dele")
    void commitEncurtado() {
        assertThat(StatusController.resolverVersao(
                "ce600ba1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7", "0.0.1-SNAPSHOT")).isEqualTo("ce600ba");
    }

    @Test
    @DisplayName("um rótulo que não é commit (MOTOSHIFT_VERSAO=v1.2) vai como veio")
    void rotuloInteiro() {
        assertThat(StatusController.resolverVersao(" v1.2 ", "0.0.1-SNAPSHOT")).isEqualTo("v1.2");
    }

    @Test
    @DisplayName("sem commit, a versão do pom; sem os dois (IDE, testes), \"dev\"")
    void semCommit() {
        assertThat(StatusController.resolverVersao("", "0.0.1-SNAPSHOT")).isEqualTo("0.0.1-SNAPSHOT");
        assertThat(StatusController.resolverVersao(null, null)).isEqualTo("dev");
        assertThat(StatusController.resolverVersao("  ", " ")).isEqualTo("dev");
    }

    @Test
    @DisplayName("o status responde a versão resolvida e não consulta nada")
    void status() {
        var resposta = new StatusController("abcdef1234567890").status();

        assertThat(resposta.ok()).isTrue();
        assertThat(resposta.versao()).isEqualTo("abcdef1");
        assertThat(resposta.fuso()).isEqualTo("America/Sao_Paulo");
        assertThat(resposta.horaServidor()).endsWith("-03:00");
    }
}
