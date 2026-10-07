package com.motoshift.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * E-mail sem diferenciar maiúsculas, de ponta a ponta: HTTP, serviço e banco.
 *
 * <p>O {@code AuthServiceTest} prende a regra com o repositório mockado — e um
 * mock responde ao que o teste mandar. Aqui o cadastro grava de verdade e o
 * login procura de verdade: se a normalização ficasse só de um dos lados
 * (grava em minúsculas, procura como veio), é este teste que cai.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class EmailSemMaiusculasTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private JdbcTemplate jdbc;

    @Test
    @DisplayName("cadastra com maiúsculas, grava em minúsculas e entra com qualquer caixa")
    void cadastroELogin_ignoramACaixa() throws Exception {
        String sufixo = UUID.randomUUID().toString().substring(0, 8);
        String comoDigitou = "Claudia." + sufixo + "@Email.Test";
        String canonico = comoDigitou.toLowerCase();

        registrar(comoDigitou)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.usuario.email").value(canonico));

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email = ?", Integer.class, canonico))
                .isEqualTo(1);

        for (String tentativa : new String[] {
                canonico, comoDigitou, canonico.toUpperCase(), "  " + comoDigitou + " "}) {
            entrar(tentativa)
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.token").isNotEmpty())
                    .andExpect(jsonPath("$.usuario.email").value(canonico));
        }
    }

    @Test
    @DisplayName("o mesmo e-mail em outra caixa não vira segunda conta: 409")
    void segundaContaComOutraCaixa_409() throws Exception {
        String sufixo = UUID.randomUUID().toString().substring(0, 8);
        registrar("maria." + sufixo + "@email.test").andExpect(status().isOk());

        registrar("MARIA." + sufixo + "@email.test")
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.mensagem").value("E-mail já cadastrado"));

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE lower(email) = ?", Integer.class,
                "maria." + sufixo + "@email.test")).isEqualTo(1);
    }

    private org.springframework.test.web.servlet.ResultActions registrar(String email) throws Exception {
        return mvc.perform(post("/api/auth/registro")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of(
                        "nome", "Conta do e-mail",
                        "email", email,
                        "telefone", "41999990000",
                        "tipo", "motoboy",
                        "documentoFederal", "12345678900",
                        "senha", "senha123"))));
    }

    private org.springframework.test.web.servlet.ResultActions entrar(String email) throws Exception {
        return mvc.perform(post("/api/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("email", email, "senha", "senha123"))));
    }
}
