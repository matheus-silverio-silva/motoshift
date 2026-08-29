package com.motoshift.service;

import com.motoshift.entity.Turno;
import com.motoshift.repository.TurnoRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

/**
 * Sugestao de turnos por IA: le o historico, monta o prompt, chama o Claude.
 *
 * O prompt era montado dentro do controller — 75 linhas de regra de produto
 * (quais janelas de horario contam, como resumir o historico, o que perguntar
 * ao modelo) em uma classe cujo trabalho e receber HTTP e devolver HTTP.
 */
@Service
public class SugestaoService {

    private static final int DIAS_DE_HISTORICO = 30;

    private final TurnoRepository turnoRepo;
    private final AnthropicService anthropic;

    public SugestaoService(TurnoRepository turnoRepo, AnthropicService anthropic) {
        this.turnoRepo = turnoRepo;
        this.anthropic = anthropic;
    }

    public Map<String, String> sugerirPara(Long motoboyId) {
        LocalDateTime desde = LocalDateTime.now().minusDays(DIAS_DE_HISTORICO);

        List<Turno> historico = turnoRepo.findByMotoboyIdAndStatusAndDataInicioAfter(
                motoboyId, "finalizado", desde);

        List<Turno> disponiveis = turnoRepo.findByStatus("aberto");

        try {
            return Map.of("sugestoes", anthropic.sugerirTurnos(
                    construirContexto(historico, disponiveis)));
        } catch (Exception e) {
            // A IA e um servico externo: quando ela cai, a resposta honesta e
            // 503, e nao um 500 que parece defeito do MotoShift.
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Serviço de sugestões temporariamente indisponível. Tente novamente.");
        }
    }

    private String construirContexto(List<Turno> historico, List<Turno> disponiveis) {
        int total = historico.size();

        BigDecimal ganhos = historico.stream()
                .map(Turno::getValorEstimado)
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

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
