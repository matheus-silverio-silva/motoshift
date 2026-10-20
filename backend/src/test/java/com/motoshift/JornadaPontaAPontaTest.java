package com.motoshift;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Teste de ponta a ponta (Entrega 4 do Projeto Integrador VI): a jornada
 * inteira do MotoShift pela API HTTP, na ordem em que o app a percorre.
 *
 * <pre>
 *  lojista e entregador se cadastram e fazem login
 *  → lojista recarrega a carteira (cobrança Pix + confirmação)
 *  → lojista publica o turno (o valor fica reservado)
 *  → entregador encontra o turno nos disponíveis e aceita
 *  → [o relógio chega ao início do turno]
 *  → entregador faz check-in no ponto do turno e check-out
 *  → lojista finaliza: o pagamento é liquidado
 *  → os dois se avaliam
 *  → a carteira de cada um mostra o dinheiro no lugar certo
 * </pre>
 *
 * <p>Só um passo não passa pelo HTTP: levar o início do turno para o passado.
 * A API só publica turno com 2h de antecedência e só deixa finalizar depois do
 * início; sem um relógio injetável, mover a data no repositório é o que faz o
 * "tempo passar" — o mesmo recurso do {@code CenarioFinanceiro}. Tudo o mais
 * (autorização, regras de turno, reserva, liquidação) roda como em produção.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class JornadaPontaAPontaTest {

    // Ponto do turno — o check-in é feito daqui, dentro do raio exigido.
    private static final double LAT = -25.4411;
    private static final double LNG = -49.2908;

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;

    @Test
    @DisplayName("cadastro → recarga → publicar → aceitar → check-in → finalizar → avaliar → carteiras")
    void jornadaCompleta() throws Exception {
        // 1. Cadastro e login dos dois lados
        String sufixo = String.valueOf(System.nanoTime());
        String emailLoja = "loja-e2e-" + sufixo + "@motoshift.test";
        String emailMoto = "moto-e2e-" + sufixo + "@motoshift.test";
        registrar("Loja E2E", emailLoja, "lojista", "11222333000144");
        registrar("Entregador E2E", emailMoto, "motoboy", "12345678900");
        JsonNode loja = login(emailLoja);
        JsonNode moto = login(emailMoto);
        String tokenLoja = "Bearer " + loja.get("token").asText();
        String tokenMoto = "Bearer " + moto.get("token").asText();
        long idMoto = idDoUsuario(moto);
        long idLoja = idDoUsuario(loja);

        // 2. Recarga da carteira do lojista
        JsonNode cobranca = corpo(mvc.perform(autenticado(post("/api/carteira/recargas"), tokenLoja)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"valor\": 300.00}"))
                .andExpect(status().isCreated()));
        mvc.perform(autenticado(post("/api/carteira/recargas/" + cobranca.get("id").asLong()
                        + "/confirmar"), tokenLoja))
                .andExpect(status().isOk());
        mvc.perform(autenticado(get("/api/carteira/resumo"), tokenLoja))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.disponivel").value(300.0));

        // 3. Publicação do turno — R$ 150 ficam reservados
        LocalDateTime inicio = LocalDateTime.now().plusHours(3).withNano(0);
        Map<String, Object> turnoReq = new LinkedHashMap<>();
        turnoReq.put("titulo", "Turno da jornada E2E");
        turnoReq.put("regiao", "Batel, Curitiba");
        turnoReq.put("dataInicio", inicio.toString());
        turnoReq.put("dataFim", inicio.plusHours(4).toString());
        turnoReq.put("valorEstimado", 150.00);
        turnoReq.put("latitude", LAT);
        turnoReq.put("longitude", LNG);
        turnoReq.put("vagas", 1);
        JsonNode turno = corpo(mvc.perform(autenticado(post("/api/turnos"), tokenLoja)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(turnoReq)))
                .andExpect(status().isCreated()));
        long idTurno = turno.get("id").asLong();
        mvc.perform(autenticado(get("/api/carteira/resumo"), tokenLoja))
                .andExpect(jsonPath("$.disponivel").value(150.0))
                .andExpect(jsonPath("$.comprometido").value(150.0));

        // 4. O entregador encontra o turno e aceita
        String disponiveis = mvc.perform(autenticado(get("/api/turnos/disponiveis"), tokenMoto))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        assertThat(json.readTree(disponiveis).findValues("id"))
                .extracting(JsonNode::asLong).contains(idTurno);
        mvc.perform(autenticado(put("/api/turnos/" + idTurno + "/aceitar"), tokenMoto))
                .andExpect(status().isOk());

        // Antes do início, finalizar é recusado (RF06)
        mvc.perform(autenticado(put("/api/turnos/" + idTurno + "/finalizar"), tokenLoja))
                .andExpect(status().isConflict());

        // 5. O tempo passa: o turno começou há um minuto
        Turno t = turnoRepo.findById(idTurno).orElseThrow();
        t.setDataInicio(LocalDateTime.now().minusMinutes(1));
        t.setDataFim(LocalDateTime.now().plusHours(4));
        turnoRepo.save(t);

        // 6. Check-in no ponto do turno e check-out
        mvc.perform(autenticado(put("/api/turnos/" + idTurno + "/checkin"), tokenMoto)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"latitude\": " + LAT + ", \"longitude\": " + LNG + "}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("em_andamento"));
        mvc.perform(autenticado(put("/api/turnos/" + idTurno + "/checkout"), tokenMoto))
                .andExpect(status().isOk());

        // 7. O lojista finaliza; repetir não paga duas vezes
        mvc.perform(autenticado(put("/api/turnos/" + idTurno + "/finalizar"), tokenLoja))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("finalizado"));
        mvc.perform(autenticado(put("/api/turnos/" + idTurno + "/finalizar"), tokenLoja))
                .andExpect(status().is4xxClientError());

        TurnoInscricao inscricao = inscricaoRepo
                .findByTurnoIdAndStatus(idTurno, StatusInscricao.ACEITO).stream()
                .filter(i -> i.getMotoboyId().equals(idMoto)).findFirst()
                .orElseGet(() -> inscricaoRepo.findAll().stream()
                        .filter(i -> i.getTurnoId().equals(idTurno)).findFirst().orElseThrow());
        assertThat(inscricao.getCheckinEm()).isNotNull();

        // 8. Avaliação mútua
        mvc.perform(autenticado(post("/api/avaliacoes"), tokenLoja)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "turnoId", idTurno, "avaliadoId", idMoto, "nota", 5,
                                "comentario", "Pontual"))))
                .andExpect(status().isCreated());
        mvc.perform(autenticado(post("/api/avaliacoes"), tokenMoto)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "turnoId", idTurno, "avaliadoId", idLoja, "nota", 4))))
                .andExpect(status().isCreated());

        // 9. O dinheiro no lugar certo
        JsonNode resumoLoja = corpo(mvc.perform(autenticado(get("/api/carteira/resumo"), tokenLoja))
                .andExpect(status().isOk()));
        assertThat(resumoLoja.get("disponivel").decimalValue()).isEqualByComparingTo("150.00");
        assertThat(resumoLoja.get("comprometido").decimalValue()).isEqualByComparingTo("0");
        assertThat(resumoLoja.get("pagoAEntregadores").decimalValue()).isEqualByComparingTo("150.00");

        JsonNode resumoMoto = corpo(mvc.perform(autenticado(get("/api/carteira/resumo"), tokenMoto))
                .andExpect(status().isOk()));
        BigDecimal recebido = resumoMoto.get("recebido").decimalValue();
        BigDecimal retencoes = resumoMoto.hasNonNull("retencoes")
                ? resumoMoto.get("retencoes").decimalValue() : BigDecimal.ZERO;
        assertThat(recebido).isEqualByComparingTo("150.00");
        assertThat(resumoMoto.get("disponivel").decimalValue())
                .isEqualByComparingTo(recebido.subtract(retencoes));
        assertThat(resumoMoto.get("aReceber").decimalValue()).isEqualByComparingTo("0");

        mvc.perform(autenticado(get("/api/carteira/extrato"), tokenMoto))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("sem token, a jornada não começa: publicar, aceitar e carteira respondem 401")
    void semTokenNadaAcontece() throws Exception {
        mvc.perform(post("/api/turnos").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isUnauthorized());
        mvc.perform(put("/api/turnos/1/aceitar")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/carteira/resumo")).andExpect(status().isUnauthorized());
    }

    // --- apoio -------------------------------------------------------------

    private void registrar(String nome, String email, String tipo, String documento) throws Exception {
        mvc.perform(post("/api/auth/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "nome", nome, "email", email, "telefone", "41999990000",
                                "tipo", tipo, "documentoFederal", documento, "senha", "senha123"))))
                .andExpect(status().isOk());
    }

    private JsonNode login(String email) throws Exception {
        return corpo(mvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("email", email, "senha", "senha123"))))
                .andExpect(status().isOk()));
    }

    /** O id vem no topo da resposta de login ou dentro de "usuario", conforme a versão. */
    private long idDoUsuario(JsonNode login) {
        if (login.hasNonNull("id")) return login.get("id").asLong();
        if (login.hasNonNull("usuarioId")) return login.get("usuarioId").asLong();
        return login.get("usuario").get("id").asLong();
    }

    private MockHttpServletRequestBuilder autenticado(MockHttpServletRequestBuilder req, String token) {
        return req.header(HttpHeaders.AUTHORIZATION, token);
    }

    private JsonNode corpo(ResultActions r) throws Exception {
        return json.readTree(r.andReturn().getResponse().getContentAsString());
    }
}
