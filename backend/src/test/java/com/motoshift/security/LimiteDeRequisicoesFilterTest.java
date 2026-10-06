package com.motoshift.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O filtro sozinho, sem Spring: de onde ele tira o IP, o que ele conta e o que
 * deixa passar (SCRUM-36).
 *
 * <p>O {@code LimiteDeRequisicoesTest} mostra o 429 saindo pelo HTTP de
 * verdade. Aqui ficam os casos que pedem controle fino — o relógio andando
 * dez minutos, o cabeçalho forjado, o perfil de dev sem proxy.
 */
class LimiteDeRequisicoesFilterTest {

    private static final long MINUTO = 60_000;

    private final RespostaDeErro erros = new RespostaDeErro(new ObjectMapper());
    private final AtomicLong agora = new AtomicLong(1_000_000);

    @AfterEach
    void limparContexto() {
        SecurityContextHolder.clearContext();
    }

    private LimiteDeRequisicoesFilter filtro(boolean habilitado, String cabecalho) {
        LimiteDeRequisicoesFilter f = new LimiteDeRequisicoesFilter(erros, habilitado, cabecalho);
        f.usarRelogio(agora::get);
        return f;
    }

    private static MockHttpServletRequest pedido(String metodo, String rota, String ip) {
        MockHttpServletRequest req = new MockHttpServletRequest(metodo, rota);
        req.setRemoteAddr(ip);
        return req;
    }

    /** Roda o filtro e devolve o status; 200 quando a requisição seguiu adiante. */
    private static MockHttpServletResponse passar(LimiteDeRequisicoesFilter f, MockHttpServletRequest req,
                                                  AtomicInteger seguiram) throws Exception {
        MockHttpServletResponse resp = new MockHttpServletResponse();
        FilterChain cadeia = (rq, rs) -> seguiram.incrementAndGet();
        f.doFilter(req, resp, cadeia);
        return resp;
    }

    // ── De onde vem o IP ──────────────────────────────────────────────────

    @Test
    @DisplayName("sem cabeçalho configurado (dev), o X-Forwarded-For é ignorado: vale o endereço da conexão")
    void semProxy_ignoraOCabecalho() {
        LimiteDeRequisicoesFilter f = filtro(true, "");
        MockHttpServletRequest req = pedido("POST", "/api/auth/registro", "10.0.0.7");
        req.addHeader("X-Forwarded-For", "203.0.113.9");
        req.addHeader("X-Real-IP", "203.0.113.9");

        assertThat(f.ipDoCliente(req)).isEqualTo("10.0.0.7");
    }

    @Test
    @DisplayName("com o cabeçalho configurado, vale a ÚLTIMA entrada — a que o proxy escreveu")
    void comProxy_ultimaEntrada() {
        LimiteDeRequisicoesFilter f = filtro(true, "X-Forwarded-For");
        MockHttpServletRequest req = pedido("POST", "/api/auth/registro", "10.0.0.7");
        // As duas primeiras são o que o cliente quis mandar; a última é a que
        // o proxy acrescentou.
        req.addHeader("X-Forwarded-For", "1.1.1.1, 2.2.2.2 , 198.51.100.23");

        assertThat(f.ipDoCliente(req)).isEqualTo("198.51.100.23");
    }

    @Test
    @DisplayName("sem o cabeçalho configurado na requisição, cai no X-Real-IP; sem nenhum, no endereço da conexão")
    void comProxy_reservas() {
        LimiteDeRequisicoesFilter f = filtro(true, "X-Forwarded-For");

        MockHttpServletRequest soRealIp = pedido("POST", "/api/auth/registro", "10.0.0.7");
        soRealIp.addHeader("X-Real-IP", "198.51.100.23");
        assertThat(f.ipDoCliente(soRealIp)).isEqualTo("198.51.100.23");

        MockHttpServletRequest vazio = pedido("POST", "/api/auth/registro", "10.0.0.7");
        vazio.addHeader("X-Forwarded-For", " , ");
        assertThat(f.ipDoCliente(vazio)).isEqualTo("10.0.0.7");
    }

    @Test
    @DisplayName("forjar a primeira entrada do X-Forwarded-For não cria um limite novo")
    void forjarOCabecalhoNaoEscapa() throws Exception {
        LimiteDeRequisicoesFilter f = filtro(true, "X-Forwarded-For");
        AtomicInteger seguiram = new AtomicInteger();

        for (int i = 0; i < LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA; i++) {
            MockHttpServletRequest req = pedido("POST", "/api/auth/registro", "10.0.0.7");
            req.addHeader("X-Forwarded-For", "8.8." + i + ".1, 198.51.100.23");
            assertThat(passar(f, req, seguiram).getStatus()).isEqualTo(200);
        }
        MockHttpServletRequest maisUma = pedido("POST", "/api/auth/registro", "10.0.0.7");
        maisUma.addHeader("X-Forwarded-For", "8.8.99.1, 198.51.100.23");

        assertThat(passar(f, maisUma, seguiram).getStatus()).isEqualTo(429);
        assertThat(seguiram.get()).isEqualTo(LimiteDeRequisicoesFilter.PUBLICAS_POR_JANELA);
    }

    // ── O que conta e o que não conta ─────────────────────────────────────

    @Test
    @DisplayName("20 em 10 minutos por IP e por rota; passados os 10 minutos, o IP volta a caber")
    void publicas_janelaDeDezMinutos() throws Exception {
        LimiteDeRequisicoesFilter f = filtro(true, "");
        AtomicInteger seguiram = new AtomicInteger();

        for (int i = 0; i < 20; i++) {
            assertThat(passar(f, pedido("POST", "/api/auth/registro", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
        }
        agora.addAndGet(4 * MINUTO);

        MockHttpServletResponse recusada =
                passar(f, pedido("POST", "/api/auth/registro", "203.0.113.5"), seguiram);
        assertThat(recusada.getStatus()).isEqualTo(429);
        // Faltam 6 dos 10 minutos.
        assertThat(recusada.getHeader("Retry-After")).isEqualTo("360");
        assertThat(recusada.getContentType()).startsWith("application/json");
        assertThat(recusada.getContentAsString())
                .contains("\"codigo\":\"muitas_tentativas\"")
                .contains("Tente de novo em 6 minuto(s).");

        // Outra rota e outro IP têm a própria conta.
        assertThat(passar(f, pedido("POST", "/api/auth/esqueci-senha", "203.0.113.5"), seguiram)
                .getStatus()).isEqualTo(200);
        assertThat(passar(f, pedido("POST", "/api/auth/registro", "203.0.113.6"), seguiram)
                .getStatus()).isEqualTo(200);

        agora.addAndGet(6 * MINUTO);
        assertThat(passar(f, pedido("POST", "/api/auth/registro", "203.0.113.5"), seguiram)
                .getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("o preflight (OPTIONS) e as rotas sem limite não gastam nada")
    void oQueNaoConta() throws Exception {
        LimiteDeRequisicoesFilter f = filtro(true, "");
        AtomicInteger seguiram = new AtomicInteger();

        for (int i = 0; i < 50; i++) {
            assertThat(passar(f, pedido("OPTIONS", "/api/auth/registro", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
            // Login tem o bloqueio próprio do RF01, por conta.
            assertThat(passar(f, pedido("POST", "/api/auth/login", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
            assertThat(passar(f, pedido("GET", "/api/turnos/disponiveis", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
        }
        // E o limite do cadastro continua inteiro.
        for (int i = 0; i < 20; i++) {
            assertThat(passar(f, pedido("POST", "/api/auth/registro", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
        }
        assertThat(passar(f, pedido("POST", "/api/auth/registro", "203.0.113.5"), seguiram)
                .getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("sugestões: 10 por hora por USUÁRIO — o IP não importa, e sem sessão nada é contado")
    void sugestoes_porUsuario() throws Exception {
        LimiteDeRequisicoesFilter f = filtro(true, "");
        AtomicInteger seguiram = new AtomicInteger();

        // Sem autenticação: segue adiante (vai morrer em 401) sem contar.
        for (int i = 0; i < 30; i++) {
            assertThat(passar(f, pedido("GET", "/api/sugestoes/turnos/7", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
        }

        logarComo(7L);
        for (int i = 0; i < 10; i++) {
            // Cada chamada de um IP diferente: a chave é a conta.
            assertThat(passar(f, pedido("GET", "/api/sugestoes/turnos/7", "203.0.113." + i), seguiram)
                    .getStatus()).isEqualTo(200);
        }
        MockHttpServletResponse recusada =
                passar(f, pedido("GET", "/api/sugestoes/turnos/7", "198.51.100.1"), seguiram);
        assertThat(recusada.getStatus()).isEqualTo(429);
        assertThat(recusada.getHeader("Retry-After")).isEqualTo("3600");

        // Outra conta, do mesmo IP, tem as suas dez.
        logarComo(8L);
        assertThat(passar(f, pedido("GET", "/api/sugestoes/turnos/8", "198.51.100.1"), seguiram)
                .getStatus()).isEqualTo(200);

        // Uma hora depois, a primeira conta volta a caber.
        agora.addAndGet(60 * MINUTO);
        logarComo(7L);
        assertThat(passar(f, pedido("GET", "/api/sugestoes/turnos/7", "198.51.100.1"), seguiram)
                .getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("desligado (MOTOSHIFT_LIMITE_HABILITADO=false), nada é recusado")
    void desligado() throws Exception {
        LimiteDeRequisicoesFilter f = filtro(false, "X-Forwarded-For");
        AtomicInteger seguiram = new AtomicInteger();

        for (int i = 0; i < 100; i++) {
            assertThat(passar(f, pedido("POST", "/api/auth/registro", "203.0.113.5"), seguiram)
                    .getStatus()).isEqualTo(200);
        }
        assertThat(seguiram.get()).isEqualTo(100);
    }

    private static void logarComo(Long id) {
        UsuarioAutenticado usuario = new UsuarioAutenticado(id, "conta" + id + "@teste.com", "motoboy");
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(usuario, null, List.of()));
    }
}
