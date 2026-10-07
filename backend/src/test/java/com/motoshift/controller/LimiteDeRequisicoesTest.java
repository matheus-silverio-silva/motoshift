package com.motoshift.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.security.LimiteDeRequisicoesFilter;
import com.motoshift.service.SugestaoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * O limite de requisições pelo HTTP de verdade (SCRUM-36): a cadeia do Spring
 * Security inteira, com o filtro no lugar em que ele roda em produção.
 *
 * <p>O limite fica desligado no perfil de teste (ver application-test), porque
 * o contexto é dividido entre as classes e todas criam contas do mesmo "IP".
 * Esta classe o liga só para ela, com o cabeçalho de proxy e um proxy
 * confiável, como no Render — e cada teste usa um IP próprio, para um não
 * gastar o limite do outro.
 *
 * <p>A conta e o relógio estão no {@code JanelaDeslizanteTest} e no
 * {@code LimiteDeRequisicoesFilterTest}; aqui a pergunta é se o 429 sai onde
 * deve, com o corpo e os cabeçalhos que o app espera.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "motoshift.limite.habilitado=true",
        "motoshift.limite.cabecalho-do-ip=X-Forwarded-For",
        "motoshift.limite.proxies-confiaveis=1"
})
class LimiteDeRequisicoesTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;

    /** A IA fica de fora: o que se testa é quantas vezes a rota deixa chamar. */
    @MockBean private SugestaoService sugestoes;

    @Test
    @DisplayName("cadastro: a 21ª requisição do mesmo IP em 10 minutos é 429, no formato de erro da API e com Retry-After")
    void registro_429() throws Exception {
        String ip = "203.0.113.10";

        for (int i = 0; i < LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA; i++) {
            // Corpo inválido de propósito: não cria conta, e conta para o
            // limite do mesmo jeito — o limite é de requisições, não de sucessos.
            cadastroInvalido(ip).andExpect(status().isBadRequest());
        }

        MvcResult recusada = cadastroInvalido(ip)
                .andExpect(status().isTooManyRequests())
                .andExpect(header().exists(HttpHeaders.RETRY_AFTER))
                .andExpect(jsonPath("$.codigo").value("muitas_tentativas"))
                .andExpect(jsonPath("$.mensagem").value("Muitas requisições. Tente de novo em 10 minuto(s)."))
                .andExpect(jsonPath("$.campo").doesNotExist())
                .andReturn();

        int segundos = Integer.parseInt(recusada.getResponse().getHeader(HttpHeaders.RETRY_AFTER));
        assertThat(segundos).isBetween(1, 600);

        // Outro IP não paga por este.
        cadastroInvalido("203.0.113.11").andExpect(status().isBadRequest());
        // E a outra rota pública tem a própria conta, mesmo para este IP.
        esqueci(ip).andExpect(status().isAccepted());
    }

    @Test
    @DisplayName("esqueci minha senha: mesmo limite, e o 429 não chega a gerar código")
    void esqueciSenha_429() throws Exception {
        String ip = "203.0.113.20";

        for (int i = 0; i < LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA; i++) {
            esqueci(ip).andExpect(status().isAccepted());
        }
        esqueci(ip)
                .andExpect(status().isTooManyRequests())
                .andExpect(header().exists(HttpHeaders.RETRY_AFTER))
                .andExpect(jsonPath("$.codigo").value("muitas_tentativas"));
    }

    @Test
    @DisplayName("o IP é a penúltima entrada do X-Forwarded-For (a última é o proxy): trocar as primeiras não escapa do limite")
    void xForwardedFor_entradaDoCliente() throws Exception {
        String ipReal = "203.0.113.30";
        String proxy = "10.210.0.5";

        for (int i = 0; i < LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA; i++) {
            cadastroInvalido("10.9.8." + i + ", " + ipReal + ", " + proxy).andExpect(status().isBadRequest());
        }
        cadastroInvalido("172.16.0.1, " + ipReal + ", " + proxy).andExpect(status().isTooManyRequests());

        // Outro cliente atrás do MESMO proxy não paga por este (SCRUM-48): era
        // o que acontecia lendo a última entrada, que é a do proxy.
        cadastroInvalido("203.0.113.31, " + proxy).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("o /api/status fica fora do limite: o monitor e o app o chamam o dia inteiro, sem token")
    void status_foraDoLimite() throws Exception {
        for (int i = 0; i < LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA * 3; i++) {
            mvc.perform(get("/api/status").header("X-Forwarded-For", "203.0.113.60, 10.210.0.5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.ok").value(true));
        }
    }

    @Test
    @DisplayName("sugestões da IA: 10 por hora por usuário; a 11ª é 429 e não chega à IA")
    void sugestoes_429() throws Exception {
        when(sugestoes.sugerirPara(any())).thenReturn(Map.of("sugestoes", "ok"));
        Conta ana = novaConta("203.0.113.40");
        Conta beto = novaConta("203.0.113.41");

        for (int i = 0; i < LimiteDeRequisicoesFilter.SUGESTOES_POR_HORA; i++) {
            pedirSugestao(ana).andExpect(status().isOk());
        }
        MvcResult recusada = pedirSugestao(ana)
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.codigo").value("muitas_tentativas"))
                .andExpect(jsonPath("$.mensagem").value("Muitas requisições. Tente de novo em 60 minuto(s)."))
                .andReturn();
        assertThat(Integer.parseInt(recusada.getResponse().getHeader(HttpHeaders.RETRY_AFTER)))
                .isBetween(1, 3600);

        // A IA foi chamada dez vezes para a Ana — a recusada parou no filtro.
        verify(sugestoes, times(LimiteDeRequisicoesFilter.SUGESTOES_POR_HORA)).sugerirPara(ana.id);

        // O limite é da conta: o Beto tem as dele.
        pedirSugestao(beto).andExpect(status().isOk());
    }

    @Test
    @DisplayName("sem token, a rota de sugestões continua 401 — o limite não vira uma resposta diferente para quem não entrou")
    void sugestoes_semToken_401() throws Exception {
        for (int i = 0; i < LimiteDeRequisicoesFilter.SUGESTOES_POR_HORA + 5; i++) {
            mvc.perform(get("/api/sugestoes/turnos/1")).andExpect(status().isUnauthorized());
        }
    }

    @Test
    @DisplayName("o 429 sai com CORS, e o Retry-After é legível pelo app web")
    void cors_noRetryAfter() throws Exception {
        String ip = "203.0.113.50";
        for (int i = 0; i < LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA; i++) {
            cadastroInvalido(ip);
        }

        mvc.perform(post("/api/auth/registro")
                        .header("X-Forwarded-For", ip)
                        .header(HttpHeaders.ORIGIN, "https://app.exemplo")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(header().exists(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_EXPOSE_HEADERS,
                        org.hamcrest.Matchers.containsString("Retry-After")));
    }

    // ── Apoio ─────────────────────────────────────────────────────────────

    private record Conta(Long id, String token) {}

    private ResultActions cadastroInvalido(String xForwardedFor) throws Exception {
        return mvc.perform(post("/api/auth/registro")
                .header("X-Forwarded-For", xForwardedFor)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"));
    }

    private ResultActions esqueci(String ip) throws Exception {
        return mvc.perform(post("/api/auth/esqueci-senha")
                .header("X-Forwarded-For", ip)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("email", "ninguem@limite.test"))));
    }

    private Conta novaConta(String ip) throws Exception {
        String sufixo = UUID.randomUUID().toString().substring(0, 8);
        String resp = mvc.perform(post("/api/auth/registro")
                        .header("X-Forwarded-For", ip)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "nome", "Conta do limite",
                                "email", "limite." + sufixo + "@email.test",
                                "telefone", "41999990000",
                                "tipo", "motoboy",
                                "documentoFederal", "12345678900",
                                "senha", "senha123"))))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        var no = json.readTree(resp);
        return new Conta(no.get("usuario").get("id").asLong(), no.get("token").asText());
    }

    private ResultActions pedirSugestao(Conta conta) throws Exception {
        return mvc.perform(get("/api/sugestoes/turnos/" + conta.id)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + conta.token));
    }
}
