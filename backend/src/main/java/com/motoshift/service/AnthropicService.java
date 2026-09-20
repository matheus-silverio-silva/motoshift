package com.motoshift.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import io.netty.channel.ChannelOption;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * A ponte com a API da Anthropic.
 *
 * <p><b>Timeout.</b> O WebClient era criado sem nenhum: a chamada e feita com
 * {@code .block()} numa thread de servlet, entao uma API lenta prendia a
 * thread ate o timeout padrao do cliente HTTP — com tres rotas chamando isto,
 * bastava a Anthropic engasgar para o servidor ficar sem thread. Agora ha
 * timeout de conexao, de resposta e um teto no proprio block.
 *
 * <p><b>Cache.</b> Cada F5 na tela era uma chamada paga. A chave e o par
 * (prompt de sistema, contexto): se os numeros do usuario nao mudaram, o
 * contexto e identico e a resposta vem do cache; se mudaram, o contexto muda e
 * a IA e consultada de novo. Isso faz a invalidacao acontecer sozinha, sem
 * ninguem precisar lembrar de limpar cache quando um turno e finalizado.
 * Limitado por tamanho e por tempo — cache sem teto vira vazamento de memoria.
 */
@Service
public class AnthropicService {

    private static final Logger log = LoggerFactory.getLogger(AnthropicService.class);

    private static final String SYSTEM_PROMPT_SUGESTAO =
            "Você é um assistente especializado no app MotoShift, plataforma de agendamento de turnos " +
            "para motoboys autônomos e lojistas. Analise o histórico do motoboy e os turnos disponíveis " +
            "e sugira os 3 melhores turnos para ele aceitar, explicando brevemente o motivo de cada " +
            "sugestão em linguagem simples e direta. Responda sempre em português brasileiro. Seja " +
            "objetivo e prático, como um colega experiente dando uma dica.";

    public static final String SYSTEM_PROMPT_RELATORIO_MOTOBOY =
            "Você é um assistente financeiro especializado para entregadores autônomos no app MotoShift. " +
            "Gere relatórios financeiros mensais personalizados, motivadores e práticos. " +
            "Responda sempre em português brasileiro com linguagem informal e positiva.";

    public static final String SYSTEM_PROMPT_RELATORIO_LOJISTA =
            "Você é um consultor operacional especializado em logística de delivery para lojistas no app MotoShift. " +
            "Gere relatórios operacionais mensais claros e com recomendações práticas de melhoria. " +
            "Responda sempre em português brasileiro com linguagem profissional mas acessível.";

    public static final String SYSTEM_PROMPT_SCORE =
            "Você é um especialista em análise de performance de entregadores autônomos no app MotoShift. " +
            "Analise o histórico de score do motoboy e forneça uma análise clara e construtiva. " +
            "O score vai de 0 a 5.0, sendo 5.0 o máximo. Penalizações ocorrem apenas por cancelamentos tardios " +
            "(menos de 1 hora de antecedência), que reduzem o score em -0.5 cada. " +
            "Responda sempre em português brasileiro com linguagem direta, honesta e encorajadora.";

    private final WebClient webClient;
    private final String model;
    private final Duration timeout;

    /** Resposta ja obtida para um par (prompt, contexto) identico. */
    private final Cache<Pergunta, String> cache;

    public AnthropicService(
            @Value("${anthropic.api.url}") String apiUrl,
            @Value("${anthropic.api.key}") String apiKey,
            @Value("${anthropic.model}") String model,
            @Value("${anthropic.timeout-segundos:20}") int timeoutSegundos,
            @Value("${anthropic.cache.minutos:15}") int cacheMinutos,
            @Value("${anthropic.cache.tamanho:500}") int cacheTamanho) {
        this.model = model;
        this.timeout = Duration.ofSeconds(timeoutSegundos);

        // O mesmo teto de 20s que o app Flutter usa nas chamadas dele: nao
        // adianta o servidor esperar mais do que o cliente vai esperar.
        HttpClient http = HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5_000)
                .responseTimeout(this.timeout);

        this.webClient = WebClient.builder()
                .baseUrl(apiUrl)
                .clientConnector(new ReactorClientHttpConnector(http))
                .defaultHeader("x-api-key", apiKey)
                .defaultHeader("anthropic-version", "2023-06-01")
                .defaultHeader("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                .build();

        this.cache = Caffeine.newBuilder()
                .maximumSize(cacheTamanho)
                .expireAfterWrite(Duration.ofMinutes(cacheMinutos))
                .build();
    }

    /** A pergunta inteira — é ela que identifica a resposta no cache. */
    private record Pergunta(String systemPrompt, String contexto) {}

    /** Envia o contexto com o systemPrompt dado e devolve o texto da resposta. */
    public String chamarClaude(String systemPrompt, String contexto) {
        if (model == null || model.isBlank()) {
            throw new IllegalStateException("Modelo Anthropic não configurado.");
        }
        return cache.get(new Pergunta(systemPrompt, contexto), this::perguntar);
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private String perguntar(Pergunta pergunta) {
        Map<String, Object> requestBody = Map.of(
                "model", model,
                "max_tokens", 1024,
                "system", pergunta.systemPrompt(),
                "messages", List.of(Map.of("role", "user", "content", pergunta.contexto()))
        );

        Map response;
        try {
            response = webClient.post()
                    .bodyValue(requestBody)
                    .retrieve()
                    .bodyToMono(Map.class)
                    // Teto no block tambem: o responseTimeout cobre a resposta,
                    // este cobre o tempo total, inclusive resolucao de nome e
                    // handshake.
                    .block(timeout.plusSeconds(5));
        } catch (WebClientResponseException e) {
            // O corpo da resposta fica no log de depuracao e nao na mensagem da
            // excecao: ele acabava no log de erro inteiro, e vai do prompt
            // enviado a detalhes da conta.
            log.warn("[anthropic] resposta {} da API", e.getStatusCode());
            log.debug("[anthropic] corpo do erro: {}", e.getResponseBodyAsString());
            throw new IllegalStateException("Erro na API Anthropic: HTTP " + e.getStatusCode(), e);
        }

        if (response == null) {
            throw new IllegalStateException("Resposta vazia da API Anthropic.");
        }

        List<Map> content = (List<Map>) response.get("content");
        if (content == null || content.isEmpty()) {
            throw new IllegalStateException("Campo 'content' ausente na resposta da API Anthropic.");
        }

        Object text = content.get(0).get("text");
        if (text == null) {
            throw new IllegalStateException("Campo 'text' ausente na resposta da API Anthropic.");
        }

        return text.toString();
    }

    /** Sugestão de turnos — mantém compatibilidade com SugestaoController. */
    public String sugerirTurnos(String contexto) {
        return chamarClaude(SYSTEM_PROMPT_SUGESTAO, contexto);
    }
}
