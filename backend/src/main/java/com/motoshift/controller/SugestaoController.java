package com.motoshift.controller;

import com.motoshift.entity.Turno;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.service.AnthropicService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.DayOfWeek;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/sugestoes")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Sugestões", description = "Sugestão inteligente de turnos via IA (Anthropic)")
public class SugestaoController {

    private final TurnoRepository turnoRepo;
    private final AnthropicService anthropicService;

    public SugestaoController(TurnoRepository turnoRepo, AnthropicService anthropicService) {
        this.turnoRepo = turnoRepo;
        this.anthropicService = anthropicService;
    }

    @Operation(
        summary = "Sugerir turnos para o motoboy",
        description = "Analisa o histórico dos últimos 30 dias e os turnos disponíveis. " +
                      "Retorna sugestão textual gerada pelo Claude (Anthropic)."
    )
    @GetMapping("/turnos/{motoboyId}")
    public Map<String, String> sugerirTurnos(@PathVariable Long motoboyId) {
        LocalDateTime trintaDiasAtras = LocalDateTime.now().minusDays(30);

        List<Turno> historico = turnoRepo.findByMotoboyIdAndStatusAndDataInicioAfter(
                motoboyId, "finalizado", trintaDiasAtras);

        List<Turno> disponiveis = turnoRepo.findByStatus("aberto");

        String contexto = construirContexto(historico, disponiveis);

        try {
            String sugestoes = anthropicService.sugerirTurnos(contexto);
            return Map.of("sugestoes", sugestoes);
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Serviço de sugestões temporariamente indisponível. Tente novamente.");
        }
    }

    private String construirContexto(List<Turno> historico, List<Turno> disponiveis) {
        int total = historico.size();

        double ganhos = historico.stream()
                .mapToDouble(Turno::getValorEstimado)
                .sum();

        String horarios = historico.stream()
                .collect(Collectors.groupingBy(
                        t -> t.getDataInicio().getHour(),
                        Collectors.counting()))
                .entrySet().stream()
                .sorted(Map.Entry.<Integer, Long>comparingByValue().reversed())
                .limit(3)
                .map(e -> String.format("%02dh", e.getKey()))
                .collect(Collectors.joining(", "));
        if (horarios.isBlank()) horarios = "Sem dados";

        String raios = historico.stream()
                .map(Turno::getRaioEntregaKm)
                .filter(r -> r != null)
                .distinct()
                .sorted()
                .map(r -> r + " km")
                .collect(Collectors.joining(", "));
        if (raios.isBlank()) raios = "Sem dados";

        String dias = historico.stream()
                .collect(Collectors.groupingBy(
                        t -> nomeDia(t.getDataInicio().getDayOfWeek()),
                        Collectors.counting()))
                .entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
                .limit(3)
                .map(e -> e.getKey() + " (" + e.getValue() + "x)")
                .collect(Collectors.joining(", "));
        if (dias.isBlank()) dias = "Sem dados";

        StringBuilder sb = new StringBuilder();
        sb.append("Histórico do motoboy nos últimos 30 dias:\n");
        sb.append(String.format("- Total de turnos concluídos: %d%n", total));
        sb.append(String.format("- Horários mais frequentes: %s%n", horarios));
        sb.append(String.format("- Raios de entrega aceitos (km): %s%n", raios));
        sb.append(String.format("- Dias da semana com mais turnos: %s%n", dias));
        sb.append(String.format("- Ganhos totais no período: R$ %.2f%n", ganhos));
        sb.append("\nTurnos disponíveis agora na plataforma:\n");

        if (disponiveis.isEmpty()) {
            sb.append("Nenhum turno disponível no momento.\n");
        } else {
            for (Turno t : disponiveis) {
                sb.append(String.format("- ID %d | Lojista %d | %s | %s - %s | Raio: %.1f km%n",
                        t.getId(),
                        t.getLojistId(),
                        t.getDataInicio().toLocalDate(),
                        t.getDataInicio().toLocalTime().toString().substring(0, 5),
                        t.getDataFim().toLocalTime().toString().substring(0, 5),
                        t.getRaioEntregaKm() != null ? t.getRaioEntregaKm() : 0.0));
            }
        }

        sb.append("\nCom base nesse perfil, quais os 3 turnos mais recomendados para este motoboy aceitar e por quê?");
        return sb.toString();
    }

    private String nomeDia(DayOfWeek dia) {
        return switch (dia) {
            case MONDAY -> "Segunda";
            case TUESDAY -> "Terça";
            case WEDNESDAY -> "Quarta";
            case THURSDAY -> "Quinta";
            case FRIDAY -> "Sexta";
            case SATURDAY -> "Sábado";
            case SUNDAY -> "Domingo";
        };
    }
}
