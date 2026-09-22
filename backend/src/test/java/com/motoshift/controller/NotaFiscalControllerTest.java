package com.motoshift.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.Map;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * As rotas novas de /api/notas-fiscais pelo HTTP: o contrato que o app lê.
 *
 * <p>A lista continua sendo um array — com ?pagina o total vai no header
 * X-Total-Count, como no resto da API —, filtro inválido é 400, e o informe
 * sai em CSV com a marca de simulação.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(CenarioFinanceiro.class)
class NotaFiscalControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private CenarioFinanceiro cenario;
    @Autowired private NotaFiscalService notas;
    @Autowired private TransactionTemplate transacoes;

    @Test
    @DisplayName("lista paginada com total no header, filtro inválido 400 e informe em CSV")
    void contrato() throws Exception {
        Conta loja = registrar("nfloja", "lojista", "11222333000144");
        Conta entregador = registrar("nfentregador", "motoboy", "12345678900");
        transacoes.executeWithoutResult(s -> {
            for (String valor : new String[]{"100.00", "80.00"}) {
                var t = cenario.turnoPago(loja.id(), valor, entregador.id());
                notas.emitir(t.getId(), entregador.id(), entregador.id());
            }
        });
        String bearer = "Bearer " + entregador.token();

        mvc.perform(get("/api/notas-fiscais").param("pagina", "0").param("tamanho", "1")
                        .header(HttpHeaders.AUTHORIZATION, bearer))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Total-Count", "2"))
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].prestadorDocumentoTipo").value("CPF"))
                .andExpect(jsonPath("$[0].tomadorDocumento").value("**.222.333/0001-**"));

        mvc.perform(get("/api/notas-fiscais").param("papel", "tomador")
                        .header(HttpHeaders.AUTHORIZATION, bearer))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));

        mvc.perform(get("/api/notas-fiscais").param("status", "rasurada")
                        .header(HttpHeaders.AUTHORIZATION, bearer))
                .andExpect(status().isBadRequest());

        mvc.perform(get("/api/notas-fiscais/resumo").header(HttpHeaders.AUTHORIZATION, bearer))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(180.00))
                .andExpect(jsonPath("$.simulado").value(true));

        mvc.perform(get("/api/notas-fiscais/resumo/exportar").header(HttpHeaders.AUTHORIZATION, bearer))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CONTENT_TYPE, startsWith("text/csv")))
                .andExpect(content().string(startsWith("DOCUMENTO SIMULADO — SEM VALOR FISCAL")))
                .andExpect(content().string(containsString("TOTAL;;180.00;")));
    }

    private record Conta(long id, String token) {}

    private Conta registrar(String apelido, String tipo, String documento) throws Exception {
        String corpo = json.writeValueAsString(Map.of(
                "nome", apelido,
                "email", apelido + "-" + System.nanoTime() + "@nftest.com",
                "telefone", "41999990000",
                "tipo", tipo,
                "documentoFederal", documento,
                "senha", "senha123"));
        String resp = mvc.perform(post("/api/auth/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        var no = json.readTree(resp);
        return new Conta(no.at("/usuario/id").asLong(), no.get("token").asText());
    }
}
