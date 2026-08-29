package com.motoshift;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A prova de que a API esta fechada — o teste que faltava.
 *
 * Ate aqui a suite media regra de negocio com mock; nada verificava quem podia
 * chamar o que. E era o buraco mais grave do projeto: 45 rotas publicas, um
 * curl lia a carteira alheia e finalizava turno dos outros. Testar isso pelo
 * service nao serve, porque a decisao mora no filtro e na cadeia do Spring
 * Security — por isso aqui sobe o contexto HTTP inteiro.
 *
 * Os tres estados que interessam, na mesma rota:
 *   sem token -> 401 | token de outra pessoa -> 403 | token do dono -> 200
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SegurancaDaApiTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper json;

    @Test
    @DisplayName("rota privada sem token responde 401")
    void semToken_401() throws Exception {
        mvc.perform(get("/api/carteira/1"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("token invalido nao vira sessao anonima — responde 401")
    void tokenInvalido_401() throws Exception {
        mvc.perform(get("/api/carteira/1")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer nao.e.um.jwt"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("carteira: o dono le a propria (200) e o vizinho leva 403")
    void carteiraAlheia_403() throws Exception {
        Conta ana  = registrarMotoboy("ana");
        Conta beto = registrarMotoboy("beto");

        mvc.perform(get("/api/carteira/" + ana.id())
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + ana.token()))
                .andExpect(status().isOk());

        // O furo original: trocar o numero na URL bastava para ver o saldo alheio.
        mvc.perform(get("/api/carteira/" + ana.id())
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + beto.token()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("saque na carteira de outra pessoa responde 403")
    void saqueAlheio_403() throws Exception {
        Conta ana  = registrarMotoboy("ana-saque");
        Conta beto = registrarMotoboy("beto-saque");

        mvc.perform(post("/api/carteira/" + ana.id() + "/saque")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + beto.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"valor\": 50.00}"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("finalizar turno de terceiro responde 403 — nao 200 como antes")
    void finalizarTurnoAlheio_403() throws Exception {
        Conta lojista = registrarLojista("padaria");
        Conta intruso = registrarMotoboy("intruso");

        long turnoId = publicarTurno(lojista, Map.of(
                "titulo", "Turno de teste",
                "dataInicio", LocalDateTime.now().plusHours(5).toString(),
                "dataFim", LocalDateTime.now().plusHours(9).toString(),
                "valorEstimado", 120.00));

        mvc.perform(put("/api/turnos/" + turnoId + "/finalizar")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + intruso.token()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("o dono do turno publicado e quem esta no token, nao quem o corpo diz")
    void lojistIdDoCorpoEIgnorado() throws Exception {
        Conta lojista = registrarLojista("dona-do-turno");

        // lojistId 999 no corpo: a tentativa de publicar em nome de outra loja.
        long turnoId = publicarTurno(lojista, Map.of(
                "lojistId", 999,
                "titulo", "Turno com dono forjado",
                "dataInicio", LocalDateTime.now().plusHours(5).toString(),
                "dataFim", LocalDateTime.now().plusHours(9).toString(),
                "valorEstimado", 100.00));

        String turno = mvc.perform(get("/api/turnos/" + turnoId)
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + lojista.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertThat(json.readTree(turno).get("lojistId").asLong()).isEqualTo(lojista.id());
    }

    @Test
    @DisplayName("motoboy nao publica turno — 403 por perfil")
    void motoboyNaoPublicaTurno_403() throws Exception {
        Conta motoboy = registrarMotoboy("sem-loja");

        String corpo = json.writeValueAsString(Map.of(
                "titulo", "Turno indevido",
                "dataInicio", LocalDateTime.now().plusHours(5).toString(),
                "dataFim", LocalDateTime.now().plusHours(9).toString(),
                "valorEstimado", 100.00));

        mvc.perform(post("/api/turnos")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + motoboy.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("login, cadastro e health seguem publicos")
    void rotasPublicasContinuamAbertas() throws Exception {
        // Credencial errada de proposito: o que importa e o 401 vir do proprio
        // login, e nao do filtro. A rota respondeu, ou seja, continua aberta.
        mvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"ninguem@teste.com\",\"senha\":\"errada\"}"))
                .andExpect(status().isUnauthorized());

        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk());
    }

    // ── Helpers ──────────────────────────────────────────────

    private record Conta(long id, String token) {}

    private Conta registrarMotoboy(String apelido) throws Exception {
        return registrar(apelido, "motoboy", "12345678900");
    }

    private Conta registrarLojista(String apelido) throws Exception {
        return registrar(apelido, "lojista", "12345678000199");
    }

    private Conta registrar(String apelido, String tipo, String documento) throws Exception {
        String corpo = json.writeValueAsString(Map.of(
                "nome", apelido,
                "email", apelido + "@segtest.com",
                "telefone", "41999990000",
                "tipo", tipo,
                "documentoFederal", documento,
                "senha", "senha123"));

        String resp = mvc.perform(post("/api/auth/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        JsonNode node = json.readTree(resp);
        return new Conta(node.get("usuario").get("id").asLong(),
                         node.get("token").asText());
    }

    private long publicarTurno(Conta lojista, Map<String, Object> corpo) throws Exception {
        String criado = mvc.perform(post("/api/turnos")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + lojista.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(corpo)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();

        return json.readTree(criado).get("id").asLong();
    }
}
