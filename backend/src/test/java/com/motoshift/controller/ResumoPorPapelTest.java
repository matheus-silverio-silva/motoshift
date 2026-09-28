package com.motoshift.controller;

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

import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * O /api/carteira/resumo pelo HTTP: cada papel recebe os seus campos, e os do
 * outro papel NÃO VÊM no JSON — nem como zero.
 *
 * <p>É o contrato que o app lê para montar os cartões dos relatórios: um campo
 * ausente é "esta pergunta não é sua", e um zero seria "a resposta é nada".
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ResumoPorPapelTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;

    @Test
    @DisplayName("o entregador recebe recebido, sacado e a receber; nada de recarga ou comprometido")
    void entregador() throws Exception {
        String token = registrar("resumo-entregador", "motoboy", "12345678900");

        mvc.perform(get("/api/carteira/resumo").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.papel").value("prestador"))
                .andExpect(jsonPath("$.recebido").value(0.0))
                .andExpect(jsonPath("$.sacado").value(0.0))
                .andExpect(jsonPath("$.aReceber").value(0.0))
                .andExpect(jsonPath("$.disponivel").value(0.0))
                .andExpect(jsonPath("$.recarregado").doesNotExist())
                .andExpect(jsonPath("$.pagoAEntregadores").doesNotExist())
                .andExpect(jsonPath("$.devolvido").doesNotExist())
                .andExpect(jsonPath("$.comprometido").doesNotExist())
                .andExpect(jsonPath("$.bloqueado").doesNotExist())
                .andExpect(jsonPath("$.reservasAbertas").doesNotExist())
                .andExpect(jsonPath("$.entradas").doesNotExist());
    }

    @Test
    @DisplayName("o lojista recebe recarregado, pago, devolvido e comprometido; nada de a receber")
    void lojista() throws Exception {
        String token = registrar("resumo-loja", "lojista", "11222333000144");

        mvc.perform(get("/api/carteira/resumo").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.papel").value("tomador"))
                .andExpect(jsonPath("$.recarregado").value(0.0))
                .andExpect(jsonPath("$.pagoAEntregadores").value(0.0))
                .andExpect(jsonPath("$.devolvido").value(0.0))
                .andExpect(jsonPath("$.comprometido").value(0.0))
                .andExpect(jsonPath("$.reservasAbertas").isArray())
                .andExpect(jsonPath("$.recebido").doesNotExist())
                .andExpect(jsonPath("$.sacado").doesNotExist())
                .andExpect(jsonPath("$.aReceber").doesNotExist())
                .andExpect(jsonPath("$.retencoes").doesNotExist())
                .andExpect(jsonPath("$.saidas").doesNotExist());
    }

    private String registrar(String apelido, String tipo, String documento) throws Exception {
        String corpo = json.writeValueAsString(Map.of(
                "nome", apelido,
                "email", apelido + "-" + System.nanoTime() + "@resumo.com",
                "telefone", "41999990000",
                "tipo", tipo,
                "documentoFederal", documento,
                "senha", "senha123"));
        String resp = mvc.perform(post("/api/auth/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return json.readTree(resp).get("token").asText();
    }
}
