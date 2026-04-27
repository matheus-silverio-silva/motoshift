package com.motoshift.controller;

import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.AnthropicService;
import com.motoshift.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/score")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Score", description = "Análise de Score com Explicação por IA")
public class ScoreController {

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final AnthropicService anthropicService;
    private final AuthService authService;

    public ScoreController(TurnoRepository turnoRepo,
                           UsuarioRepository usuarioRepo,
                           AnthropicService anthropicService,
                           AuthService authService) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.anthropicService = anthropicService;
        this.authService = authService;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/score/{motoboyId}/analise
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Análise de score do Motoboy",
               description = "Retorna análise detalhada do score via IA. Requer token Bearer no header Authorization.")
    @GetMapping("/{motoboyId}/analise")
    public Map<String, Object> analisarScore(
            @PathVariable Long motoboyId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        Long tokenUserId = extrairEValidar(authHeader);
        if (!tokenUserId.equals(motoboyId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: você só pode acessar seu próprio score.");
        }

        Usuario motoboy = usuarioRepo.findById(motoboyId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Motoboy não encontrado."));
        if (!"motoboy".equals(motoboy.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Endpoint exclusivo para perfil motoboy.");
        }

        double scoreAtual = motoboy.getScore() != null ? motoboy.getScore() : 5.0;
        LocalDateTime agora = LocalDateTime.now();
        LocalDateTime inicio30d = agora.minusDays(30);

        List<Turno> todosTurnos = turnoRepo.findByMotoboyId(motoboyId);

        // Cancelamentos tardios nos últimos 30 dias:
        // tardio = atualizadoEm depois de (dataInicio - 1h), ou seja, cancelou com menos de 1h de antecedência
        List<Turno> canceladosTardios30d = todosTurnos.stream()
                .filter(t -> "cancelado".equals(t.getStatus()))
                .filter(t -> t.getDataInicio() != null && !t.getDataInicio().isBefore(inicio30d))
                .filter(t -> t.getAtualizadoEm() != null
                        && t.getAtualizadoEm().isAfter(t.getDataInicio().minusHours(1)))
                .collect(Collectors.toList());

        // Estima score 30 dias atrás revertendo penalizações recentes
        double scoreAnterior = Math.min(5.0, scoreAtual + canceladosTardios30d.size() * 0.5);
        double variacao = Math.round((scoreAtual - scoreAnterior) * 10.0) / 10.0;
        String tendencia = variacao > 0 ? "up" : (variacao < 0 ? "down" : "stable");

        String classificacao;
        if (scoreAtual >= 4.5) classificacao = "Excelente";
        else if (scoreAtual >= 3.5) classificacao = "Bom";
        else if (scoreAtual >= 2.5) classificacao = "Regular";
        else classificacao = "Baixo";

        List<Turno> finalizados30d = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .filter(t -> t.getDataInicio() != null && !t.getDataInicio().isBefore(inicio30d))
                .collect(Collectors.toList());

        long cancelados30d = todosTurnos.stream()
                .filter(t -> "cancelado".equals(t.getStatus()))
                .filter(t -> t.getDataInicio() != null && !t.getDataInicio().isBefore(inicio30d))
                .count();

        // Últimos 10 eventos (finalizados + cancelados) ordenados por data desc
        List<Map<String, Object>> eventos = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()) || "cancelado".equals(t.getStatus()))
                .filter(t -> t.getDataInicio() != null)
                .sorted(Comparator.comparing(Turno::getDataInicio).reversed())
                .limit(10)
                .map(t -> {
                    boolean tardio = "cancelado".equals(t.getStatus())
                            && t.getAtualizadoEm() != null
                            && t.getAtualizadoEm().isAfter(t.getDataInicio().minusHours(1));
                    String tipo = "finalizado".equals(t.getStatus()) ? "finalizado"
                            : (tardio ? "cancelado_tardio" : "cancelado");
                    double impacto = tardio ? -0.5 : 0.0;

                    Map<String, Object> ev = new HashMap<>();
                    ev.put("tipo", tipo);
                    ev.put("titulo", t.getTitulo());
                    ev.put("data", t.getDataInicio().format(DateTimeFormatter.ofPattern("dd/MM/yyyy")));
                    ev.put("impacto", impacto);
                    return ev;
                })
                .collect(Collectors.toList());

        String contexto = String.format(
                "Análise de score do motoboy nos últimos 30 dias:%n" +
                "- Nome: %s%n" +
                "- Score atual: %.2f/5.0%n" +
                "- Score estimado há 30 dias: %.2f/5.0%n" +
                "- Variação: %+.1f%n" +
                "- Classificação atual: %s%n" +
                "- Turnos concluídos nos últimos 30 dias: %d%n" +
                "- Turnos cancelados nos últimos 30 dias: %d%n" +
                "- Cancelamentos tardios (< 1h de antecedência, penalizam -0.5 cada): %d%n%n" +
                "Regras de score do MotoShift:%n" +
                "- Score inicial: 5.0%n" +
                "- Cancelamento com menos de 1h de antecedência: -0.5%n" +
                "- Concluir turnos: sem impacto direto no score%n%n" +
                "Forneça uma análise do score deste motoboy. Inclua:%n" +
                "1. Interpretação do score atual em 1-2 frases%n" +
                "2. O que está indo bem ou o que causou a variação%n" +
                "3. Uma dica prática para manter ou melhorar o score%n" +
                "Linguagem direta e encorajadora. Máximo 120 palavras.",
                motoboy.getNome(), scoreAtual, scoreAnterior, variacao,
                classificacao, finalizados30d.size(), cancelados30d, canceladosTardios30d.size());

        try {
            String analise = anthropicService.chamarClaude(AnthropicService.SYSTEM_PROMPT_SCORE, contexto);

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("scoreAtual", scoreAtual);
            result.put("scoreAnterior", scoreAnterior);
            result.put("variacao", variacao);
            result.put("tendencia", tendencia);
            result.put("classificacao", classificacao);
            result.put("analise", analise);
            result.put("ultimaAtualizacao",
                    LocalDate.now().format(DateTimeFormatter.ofPattern("dd/MM/yyyy")));
            result.put("eventos", eventos);
            return result;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Serviço de análise de score temporariamente indisponível. Tente novamente.");
        }
    }

    // ─────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────

    private Long extrairEValidar(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                    "Token de autenticação obrigatório.");
        }
        return authService.validarToken(authHeader.substring(7));
    }
}
