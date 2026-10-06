package com.motoshift.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.service.SenhaService;
import com.motoshift.service.email.EnvioDeEmail;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Trocar e recuperar a senha, de ponta a ponta: HTTP, serviço e banco (SCRUM-32).
 *
 * <p>O envio de e-mail é a única peça trocada: no lugar do
 * {@code EnvioDeEmailSimulado}, que escreve no log, entra um mock — é dele que
 * o teste lê o código, como a pessoa leria da caixa de entrada. O resto é o
 * sistema de verdade: o BCrypt confere, o banco grava, o filtro do JWT barra.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SenhaPeloHttpTest {

    private static final String SENHA = "senha123";
    private static final String NOVA = "outra-senha-456";
    private static final String CODIGO_INVALIDO = "Código inválido ou expirado. Peça um novo código.";

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private PasswordEncoder encoder;

    @MockBean private EnvioDeEmail email;

    // ── Trocar a senha (logado) ───────────────────────────────────────────

    @Nested
    @DisplayName("POST /api/auth/trocar-senha")
    class Trocar {

        @Test
        @DisplayName("sem token é 401: a rota mora em /api/auth, mas não é pública")
        void semToken_401() throws Exception {
            mvc.perform(post("/api/auth/trocar-senha")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(corpo("senhaAtual", SENHA, "senhaNova", NOVA)))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.codigo").value("nao_autenticado"));
        }

        @Test
        @DisplayName("troca: a senha antiga deixa de entrar e a nova entra")
        void sucesso() throws Exception {
            Conta conta = novaConta();

            trocar(conta.token, SENHA, NOVA).andExpect(status().isNoContent());

            entrar(conta.email, SENHA).andExpect(status().isUnauthorized());
            entrar(conta.email, NOVA).andExpect(status().isOk());
            // Gravada como hash, igual à do cadastro.
            assertThat(senhaGravada(conta.email)).startsWith("$2").isNotEqualTo(NOVA);
        }

        @Test
        @DisplayName("senha atual errada é 400 — e nem cinco erros contam como tentativa de login")
        void senhaAtualErrada_400_semContarTentativa() throws Exception {
            Conta conta = novaConta();

            for (int i = 0; i < 6; i++) {
                trocar(conta.token, "nao-e-esta", NOVA)
                        .andExpect(status().isBadRequest())
                        .andExpect(jsonPath("$.codigo").value("requisicao_invalida"))
                        .andExpect(jsonPath("$.mensagem").value("A senha atual não confere."));
            }

            assertThat(jdbc.queryForObject(
                    "SELECT tentativas_login FROM usuarios WHERE email = ?", Integer.class, conta.email))
                    .isZero();
            assertThat(jdbc.queryForObject(
                    "SELECT bloqueado_ate FROM usuarios WHERE email = ?", Timestamp.class, conta.email))
                    .isNull();
            // A conta não foi bloqueada, e a senha continua a de antes.
            entrar(conta.email, SENHA).andExpect(status().isOk());
        }

        @Test
        @DisplayName("senha nova com menos de 6 caracteres é 400, apontando o campo")
        void senhaNovaCurta_400() throws Exception {
            Conta conta = novaConta();

            trocar(conta.token, SENHA, "12345")
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.campo").value("senhaNova"))
                    .andExpect(jsonPath("$.mensagem").value("A senha deve ter no mínimo 6 caracteres"));

            entrar(conta.email, SENHA).andExpect(status().isOk());
        }

        @Test
        @DisplayName("trocar a senha invalida o código de recuperação que estava pendente")
        void trocaApagaCodigoPendente() throws Exception {
            Conta conta = novaConta();
            String codigo = pedirCodigo(conta.email);

            trocar(conta.token, SENHA, NOVA).andExpect(status().isNoContent());

            redefinir(conta.email, codigo, "terceira-789")
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));
            entrar(conta.email, NOVA).andExpect(status().isOk());
        }
    }

    // ── Esqueci minha senha ───────────────────────────────────────────────

    @Nested
    @DisplayName("POST /api/auth/esqueci-senha")
    class Esqueci {

        @Test
        @DisplayName("e-mail sem conta: 202 com a mesma resposta, e nada é enviado nem gravado")
        void semConta_202_semEnvio() throws Exception {
            long antes = codigosNoBanco();

            esqueci("ninguem." + sufixo() + "@email.test")
                    .andExpect(status().isAccepted())
                    .andExpect(jsonPath("$.mensagem").value(
                            "Se houver uma conta com este e-mail, enviamos um código de 6 dígitos para ele."));

            verify(email, never()).enviar(any(), any(), any());
            assertThat(codigosNoBanco()).isEqualTo(antes);
        }

        @Test
        @DisplayName("e-mail com conta: 202 igual, o código vai por e-mail e o banco guarda só o hash")
        void comConta_202_gravaSoOHash() throws Exception {
            Conta conta = novaConta();

            esqueci(conta.email)
                    .andExpect(status().isAccepted())
                    .andExpect(jsonPath("$.mensagem").value(
                            "Se houver uma conta com este e-mail, enviamos um código de 6 dígitos para ele."));

            String codigo = codigoEnviadoPara(conta.email);
            assertThat(codigo).matches("\\d{6}");

            Map<String, Object> linha = jdbc.queryForMap(
                    "SELECT c.codigo_hash, c.criado_em, c.expira_em, c.tentativas "
                  + "FROM codigos_recuperacao_senha c JOIN usuarios u ON u.id = c.usuario_id "
                  + "WHERE u.email = ?", conta.email);
            String hash = (String) linha.get("CODIGO_HASH");
            assertThat(hash).startsWith("$2").doesNotContain(codigo);
            assertThat(encoder.matches(codigo, hash)).isTrue();
            assertThat(((Number) linha.get("TENTATIVAS")).intValue()).isZero();

            LocalDateTime criado = ((Timestamp) linha.get("CRIADO_EM")).toLocalDateTime();
            LocalDateTime expira = ((Timestamp) linha.get("EXPIRA_EM")).toLocalDateTime();
            assertThat(ChronoUnit.MINUTES.between(criado, expira))
                    .isEqualTo(SenhaService.VALIDADE_DO_CODIGO_MINUTOS);
        }

        @Test
        @DisplayName("o e-mail não diferencia maiúsculas, como no login")
        void emailEmOutraCaixa() throws Exception {
            Conta conta = novaConta();

            esqueci("  " + conta.email.toUpperCase() + " ").andExpect(status().isAccepted());

            assertThat(codigoEnviadoPara(conta.email)).matches("\\d{6}");
        }

        @Test
        @DisplayName("e-mail malformado é 400")
        void emailMalformado_400() throws Exception {
            esqueci("isto-nao-e-email")
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.campo").value("email"));
        }

        @Test
        @DisplayName("segundo pedido em seguida não gera outro código; passado o intervalo, o novo aposenta o antigo")
        void intervaloEntreCodigos() throws Exception {
            Conta conta = novaConta();
            String primeiro = pedirCodigo(conta.email);

            // Dentro do intervalo: aceito, ignorado, e o primeiro continua valendo.
            clearInvocations(email);
            esqueci(conta.email).andExpect(status().isAccepted());
            verify(email, never()).enviar(any(), any(), any());
            assertThat(codigosDe(conta.email)).isEqualTo(1);

            // Passado o intervalo: código novo, e só ele vale.
            envelhecerCodigo(conta.email, SenhaService.INTERVALO_ENTRE_CODIGOS_SEGUNDOS + 5);
            String segundo = pedirCodigo(conta.email);
            assertThat(codigosDe(conta.email)).isEqualTo(1);

            if (!primeiro.equals(segundo)) {
                redefinir(conta.email, primeiro, NOVA).andExpect(status().isBadRequest());
            }
            redefinir(conta.email, segundo, NOVA).andExpect(status().isNoContent());
        }
    }

    // ── Redefinir com o código ────────────────────────────────────────────

    @Nested
    @DisplayName("POST /api/auth/redefinir-senha")
    class Redefinir {

        @Test
        @DisplayName("código certo: a senha nova entra, a antiga não, e o código não vale duas vezes")
        void codigoCerto() throws Exception {
            Conta conta = novaConta();
            String codigo = pedirCodigo(conta.email);

            redefinir(conta.email, codigo, NOVA).andExpect(status().isNoContent());

            entrar(conta.email, SENHA).andExpect(status().isUnauthorized());
            entrar(conta.email, NOVA).andExpect(status().isOk());
            assertThat(codigosDe(conta.email)).isZero();

            redefinir(conta.email, codigo, "terceira-789")
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));
            entrar(conta.email, NOVA).andExpect(status().isOk());
        }

        @Test
        @DisplayName("código errado é 400 e gasta uma tentativa; o certo ainda vale depois")
        void codigoErrado_400() throws Exception {
            Conta conta = novaConta();
            String codigo = pedirCodigo(conta.email);

            redefinir(conta.email, outroCodigo(codigo), NOVA)
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.codigo").value("requisicao_invalida"))
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));

            assertThat(tentativasDe(conta.email)).isEqualTo(1);
            entrar(conta.email, SENHA).andExpect(status().isOk());

            redefinir(conta.email, codigo, NOVA).andExpect(status().isNoContent());
        }

        @Test
        @DisplayName("no quinto erro o código morre: nem o certo passa mais")
        void cincoErros_matamOCodigo() throws Exception {
            Conta conta = novaConta();
            String codigo = pedirCodigo(conta.email);

            for (int i = 0; i < SenhaService.MAX_TENTATIVAS_POR_CODIGO; i++) {
                redefinir(conta.email, outroCodigo(codigo), NOVA).andExpect(status().isBadRequest());
            }
            assertThat(tentativasDe(conta.email)).isEqualTo(SenhaService.MAX_TENTATIVAS_POR_CODIGO);

            redefinir(conta.email, codigo, NOVA)
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));

            // O contador para no limite, e a senha é a de antes.
            assertThat(tentativasDe(conta.email)).isEqualTo(SenhaService.MAX_TENTATIVAS_POR_CODIGO);
            entrar(conta.email, SENHA).andExpect(status().isOk());
            entrar(conta.email, NOVA).andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("código vencido (15 minutos) é 400, mesmo sendo o certo")
        void codigoExpirado_400() throws Exception {
            Conta conta = novaConta();
            String codigo = pedirCodigo(conta.email);
            jdbc.update("UPDATE codigos_recuperacao_senha SET expira_em = ? "
                      + "WHERE usuario_id = (SELECT id FROM usuarios WHERE email = ?)",
                    Timestamp.valueOf(LocalDateTime.now().minusSeconds(1)), conta.email);

            redefinir(conta.email, codigo, NOVA)
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));

            // Vencido não chega a ser conferido: não gasta tentativa.
            assertThat(tentativasDe(conta.email)).isZero();
            entrar(conta.email, SENHA).andExpect(status().isOk());
        }

        @Test
        @DisplayName("e-mail sem conta e conta sem pedido respondem igual ao código errado")
        void semContaOuSemPedido_mesmaResposta() throws Exception {
            redefinir("ninguem." + sufixo() + "@email.test", "123456", NOVA)
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));

            Conta semPedido = novaConta();
            redefinir(semPedido.email, "123456", NOVA)
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value(CODIGO_INVALIDO));
            entrar(semPedido.email, SENHA).andExpect(status().isOk());
        }

        @Test
        @DisplayName("código que não tem 6 dígitos é 400 no campo, sem gastar tentativa")
        void codigoMalformado_naoGastaTentativa() throws Exception {
            Conta conta = novaConta();
            pedirCodigo(conta.email);

            for (String malformado : new String[] {"12345", "1234567", "abcdef", ""}) {
                redefinir(conta.email, malformado, NOVA)
                        .andExpect(status().isBadRequest())
                        .andExpect(jsonPath("$.campo").value("codigo"));
            }
            assertThat(tentativasDe(conta.email)).isZero();
        }

        @Test
        @DisplayName("senha nova com menos de 6 caracteres é 400 e não gasta o código")
        void senhaNovaCurta_400() throws Exception {
            Conta conta = novaConta();
            String codigo = pedirCodigo(conta.email);

            redefinir(conta.email, codigo, "12345")
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.campo").value("senhaNova"));

            assertThat(tentativasDe(conta.email)).isZero();
            redefinir(conta.email, codigo, NOVA).andExpect(status().isNoContent());
        }

        @Test
        @DisplayName("redefinir destrava a conta que o login tinha bloqueado")
        void redefinirDestravaOLogin() throws Exception {
            Conta conta = novaConta();
            for (int i = 0; i < 5; i++) {
                entrar(conta.email, "errada-" + i);
            }
            entrar(conta.email, SENHA).andExpect(status().isTooManyRequests());

            String codigo = pedirCodigo(conta.email);
            redefinir(conta.email, codigo, NOVA).andExpect(status().isNoContent());

            entrar(conta.email, NOVA).andExpect(status().isOk());
        }
    }

    // ── Apoio ─────────────────────────────────────────────────────────────

    private record Conta(String email, String token) {}

    private static String sufixo() {
        return UUID.randomUUID().toString().substring(0, 8);
    }

    private Conta novaConta() throws Exception {
        String endereco = "senha." + sufixo() + "@email.test";
        String resp = mvc.perform(post("/api/auth/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "nome", "Conta da senha",
                                "email", endereco,
                                "telefone", "41999990000",
                                "tipo", "motoboy",
                                "documentoFederal", "12345678900",
                                "senha", SENHA))))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return new Conta(endereco, json.readTree(resp).get("token").asText());
    }

    private String corpo(String... paresChaveValor) throws Exception {
        Map<String, String> m = new java.util.LinkedHashMap<>();
        for (int i = 0; i < paresChaveValor.length; i += 2) {
            m.put(paresChaveValor[i], paresChaveValor[i + 1]);
        }
        return json.writeValueAsString(m);
    }

    private ResultActions entrar(String endereco, String senha) throws Exception {
        return mvc.perform(post("/api/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo("email", endereco, "senha", senha)));
    }

    private ResultActions trocar(String token, String atual, String nova) throws Exception {
        return mvc.perform(post("/api/auth/trocar-senha")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo("senhaAtual", atual, "senhaNova", nova)));
    }

    private ResultActions esqueci(String endereco) throws Exception {
        return mvc.perform(post("/api/auth/esqueci-senha")
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo("email", endereco)));
    }

    private ResultActions redefinir(String endereco, String codigo, String nova) throws Exception {
        return mvc.perform(post("/api/auth/redefinir-senha")
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo("email", endereco, "codigo", codigo, "senhaNova", nova)));
    }

    /** Pede o código e o lê do "e-mail" — o único lugar em que ele existe em claro. */
    private String pedirCodigo(String endereco) throws Exception {
        clearInvocations(email);
        esqueci(endereco).andExpect(status().isAccepted());
        return codigoEnviadoPara(endereco);
    }

    private String codigoEnviadoPara(String endereco) {
        ArgumentCaptor<String> mensagem = ArgumentCaptor.forClass(String.class);
        verify(email, atLeastOnce()).enviar(eq(endereco), any(), mensagem.capture());
        Matcher m = Pattern.compile("\\b(\\d{6})\\b").matcher(mensagem.getValue());
        assertThat(m.find()).as("o e-mail traz o código de 6 dígitos").isTrue();
        return m.group(1);
    }

    /** Um código de 6 dígitos que com certeza não é o certo. */
    private static String outroCodigo(String certo) {
        return String.format("%06d", (Integer.parseInt(certo) + 1) % 1_000_000);
    }

    private long codigosNoBanco() {
        return jdbc.queryForObject("SELECT count(*) FROM codigos_recuperacao_senha", Long.class);
    }

    private long codigosDe(String endereco) {
        return jdbc.queryForObject(
                "SELECT count(*) FROM codigos_recuperacao_senha c JOIN usuarios u ON u.id = c.usuario_id "
              + "WHERE u.email = ?", Long.class, endereco);
    }

    private int tentativasDe(String endereco) {
        return jdbc.queryForObject(
                "SELECT c.tentativas FROM codigos_recuperacao_senha c JOIN usuarios u ON u.id = c.usuario_id "
              + "WHERE u.email = ?", Integer.class, endereco);
    }

    private String senhaGravada(String endereco) {
        return jdbc.queryForObject("SELECT senha FROM usuarios WHERE email = ?", String.class, endereco);
    }

    /** Faz de conta que o código foi pedido há {@code segundos} segundos. */
    private void envelhecerCodigo(String endereco, int segundos) {
        jdbc.update("UPDATE codigos_recuperacao_senha SET criado_em = ? "
                  + "WHERE usuario_id = (SELECT id FROM usuarios WHERE email = ?)",
                Timestamp.valueOf(LocalDateTime.now().minusSeconds(segundos)), endereco);
    }
}
