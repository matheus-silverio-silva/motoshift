package com.motoshift.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import java.util.List;
import java.util.Map;

@Service
public class AnthropicService {

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

    public AnthropicService(
            @Value("${anthropic.api.url}") String apiUrl,
            @Value("${anthropic.api.key}") String apiKey,
            @Value("${anthropic.model}") String model) {
        this.model = model;
        this.webClient = WebClient.builder()
                .baseUrl(apiUrl)
                .defaultHeader("x-api-key", apiKey)
                .defaultHeader("anthropic-version", "2023-06-01")
                .defaultHeader("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                .build();
    }

    /** Método genérico: envia contexto com o systemPrompt dado e retorna o texto da resposta. */
    @SuppressWarnings({"unchecked", "rawtypes"})
    public String chamarClaude(String systemPrompt, String contexto) {
        if (model == null || model.isBlank()) {
            throw new IllegalStateException("Modelo Anthropic não configurado.");
        }

        Map<String, Object> requestBody = Map.of(
                "model", model,
                "max_tokens", 1024,
                "system", systemPrompt,
                "messages", List.of(Map.of("role", "user", "content", contexto))
        );

        Map response;
        try {
            response = webClient.post()
                    .bodyValue(requestBody)
                    .retrieve()
                    .bodyToMono(Map.class)
                    .block();
        } catch (WebClientResponseException e) {
            throw new RuntimeException("Erro na API Anthropic (" + e.getStatusCode() + "): " + e.getResponseBodyAsString(), e);
        }

        if (response == null) {
            throw new RuntimeException("Resposta vazia da API Anthropic.");
        }

        List<Map> content = (List<Map>) response.get("content");
        if (content == null || content.isEmpty()) {
            throw new RuntimeException("Campo 'content' ausente na resposta da API Anthropic.");
        }

        Object text = content.get(0).get("text");
        if (text == null) {
            throw new RuntimeException("Campo 'text' ausente na resposta da API Anthropic.");
        }

        return text.toString();
    }

    /** Sugestão de turnos — mantém compatibilidade com SugestaoController. */
    public String sugerirTurnos(String contexto) {
        return chamarClaude(SYSTEM_PROMPT_SUGESTAO, contexto);
    }
}
