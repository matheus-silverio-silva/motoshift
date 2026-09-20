package com.motoshift.service;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * A conversa com a API da Anthropic, contra um servidor HTTP de mentira.
 *
 * As tres coisas que mudaram aqui não dá para verificar com mock do WebClient:
 * quantas chamadas SAEM (cache), o que acontece quando a resposta não vem
 * (timeout) e o que vai parar na mensagem de erro.
 */
class AnthropicServiceTest {

    private HttpServer servidor;
    private final AtomicInteger chamadas = new AtomicInteger();

    @BeforeEach
    void subirServidor() throws IOException {
        servidor = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    }

    @AfterEach
    void derrubarServidor() {
        servidor.stop(0);
    }

    @Test
    @DisplayName("a mesma pergunta em seguida nao repete a chamada paga")
    void cacheEvitaChamadaRepetida() {
        responder(200, "{\"content\":[{\"text\":\"tudo certo\"}]}");
        AnthropicService anthropic = servico(20, 15);

        String primeira = anthropic.chamarClaude("prompt", "contexto do usuario 7");
        String segunda = anthropic.chamarClaude("prompt", "contexto do usuario 7");

        assertThat(primeira).isEqualTo("tudo certo");
        assertThat(segunda).isEqualTo("tudo certo");
        assertThat(chamadas.get()).isEqualTo(1);
    }

    @Test
    @DisplayName("contexto diferente é pergunta diferente — cache não mascara dado novo")
    void contextoDiferenteConsultaDeNovo() {
        responder(200, "{\"content\":[{\"text\":\"ok\"}]}");
        AnthropicService anthropic = servico(20, 15);

        // O contexto carrega os numeros do usuario: quando um turno e
        // finalizado, ele muda — e e assim que o cache se invalida sozinho.
        anthropic.chamarClaude("prompt", "score 4.7");
        anthropic.chamarClaude("prompt", "score 4.2");

        assertThat(chamadas.get()).isEqualTo(2);
    }

    @Test
    @DisplayName("resposta que nao chega vira erro em segundos, e nao thread presa")
    void timeoutNaoPrendeAThread() {
        servidor.createContext("/v1/messages", troca -> {
            chamadas.incrementAndGet();
            try {
                Thread.sleep(5_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            troca.sendResponseHeaders(200, 0);
            troca.close();
        });
        servidor.start();
        AnthropicService anthropic = servico(1, 15);

        long inicio = System.currentTimeMillis();
        assertThatThrownBy(() -> anthropic.chamarClaude("prompt", "contexto"))
                .isInstanceOf(RuntimeException.class);

        // Sem responseTimeout isto esperava o padrao do cliente HTTP, com a
        // thread do servlet presa junto.
        assertThat(System.currentTimeMillis() - inicio).isLessThan(4_000);
    }

    @Test
    @DisplayName("o corpo do erro da API nao vaza para a mensagem da excecao")
    void erroNaoVazaCorpo() {
        responder(400, "{\"error\":{\"message\":\"prompt com dados do usuario e detalhes da conta\"}}");
        AnthropicService anthropic = servico(20, 15);

        assertThatThrownBy(() -> anthropic.chamarClaude("prompt", "contexto"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("400")
                .hasMessageNotContaining("dados do usuario");
    }

    // ── Apoio ────────────────────────────────────────────────────────────────

    private void responder(int status, String corpo) {
        servidor.createContext("/v1/messages", troca -> {
            chamadas.incrementAndGet();
            byte[] bytes = corpo.getBytes(StandardCharsets.UTF_8);
            troca.getResponseHeaders().add("Content-Type", "application/json");
            troca.sendResponseHeaders(status, bytes.length);
            try (OutputStream out = troca.getResponseBody()) {
                out.write(bytes);
            }
        });
        servidor.start();
    }

    private AnthropicService servico(int timeoutSegundos, int cacheMinutos) {
        String url = "http://127.0.0.1:" + servidor.getAddress().getPort() + "/v1/messages";
        return new AnthropicService(url, "chave-de-teste", "claude-teste",
                timeoutSegundos, cacheMinutos, 100);
    }
}
