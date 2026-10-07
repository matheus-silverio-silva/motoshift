package com.motoshift.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.head;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /api/status} pelo HTTP de verdade (SCRUM-48): pública, com a hora
 * e o fuso do servidor.
 *
 * <p>É também o teste do fuso com a aplicação no ar: o contexto sobe e o
 * "agora" que ele responde é o de Brasília. Que a rota fica fora do limite de
 * requisições está no {@code LimiteDeRequisicoesTest}, que é quem liga o
 * limite.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class StatusHttpTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;

    @Test
    @DisplayName("sem token: 200 com ok, hora do servidor, fuso e versão")
    void semToken_200() throws Exception {
        String corpo = mvc.perform(get("/api/status"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ok").value(true))
                .andExpect(jsonPath("$.fuso").value("America/Sao_Paulo"))
                .andExpect(jsonPath("$.versao").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        JsonNode no = json.readTree(corpo);
        // Só os quatro campos: nada de banco, nada de configuração.
        assertThat(no.size()).isEqualTo(4);

        // A hora vem com o deslocamento, para quem confere o deploy não ter de
        // adivinhar em que fuso ela está.
        OffsetDateTime hora = OffsetDateTime.parse(no.get("horaServidor").asText());
        assertThat(hora.getOffset()).isEqualTo(ZoneOffset.ofHours(-3));
        assertThat(Duration.between(hora, OffsetDateTime.now(ZoneId.of("America/Sao_Paulo"))).abs())
                .isLessThan(Duration.ofMinutes(1));
    }

    @Test
    @DisplayName("HEAD também responde 200: é o método que alguns monitores usam por padrão")
    void head_200() throws Exception {
        mvc.perform(head("/api/status")).andExpect(status().isOk());
    }

    @Test
    @DisplayName("o app web chama de outra origem: a resposta sai com CORS")
    void comCors() throws Exception {
        mvc.perform(get("/api/status").header(HttpHeaders.ORIGIN, "https://app.exemplo"))
                .andExpect(status().isOk())
                .andExpect(header().exists(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
    }

    @Test
    @DisplayName("pública é só essa rota: o que vier abaixo dela pede token")
    void soEssaRota() throws Exception {
        mvc.perform(get("/api/status/qualquer-coisa")).andExpect(status().isUnauthorized());
    }
}
