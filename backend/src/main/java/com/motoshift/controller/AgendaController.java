package com.motoshift.controller;

import com.motoshift.entity.Turno;
import com.motoshift.repository.TurnoRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/agenda")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Agenda", description = "Calendário de turnos por mês ou semana")
public class AgendaController {

    private final TurnoRepository turnoRepo;

    public AgendaController(TurnoRepository turnoRepo) {
        this.turnoRepo = turnoRepo;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/agenda/{usuarioId}?mes={MM}&ano={YYYY}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Agenda mensal",
               description = "Retorna todos os turnos do mês agrupados por dia.")
    @GetMapping("/{usuarioId}")
    public Map<String, Object> agendaMensal(
            @PathVariable Long usuarioId,
            @RequestParam int mes,
            @RequestParam int ano) {

        LocalDateTime inicio = LocalDateTime.of(ano, mes, 1, 0, 0);
        LocalDateTime fim    = inicio.plusMonths(1);

        List<Turno> turnos = turnoRepo.findByUsuarioAndPeriodo(usuarioId, inicio, fim);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("mes", mes);
        result.put("ano", ano);
        result.put("dias", agruparPorDia(turnos));
        return result;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/agenda/{usuarioId}/semana?data={YYYY-MM-DD}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Agenda semanal",
               description = "Retorna turnos dos 7 dias a partir da data informada.")
    @GetMapping("/{usuarioId}/semana")
    public Map<String, Object> agendaSemanal(
            @PathVariable Long usuarioId,
            @RequestParam String data) {

        LocalDate  dataBase = LocalDate.parse(data);
        LocalDateTime inicio = dataBase.atStartOfDay();
        LocalDateTime fim    = inicio.plusDays(7);

        List<Turno> turnos = turnoRepo.findByUsuarioAndPeriodo(usuarioId, inicio, fim);

        // Agrupa por dia e garante que todos os 7 dias apareçam
        Map<String, List<Map<String, Object>>> porDia = agruparPorDiaMap(turnos);

        List<Map<String, Object>> dias = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            String dStr = dataBase.plusDays(i).toString();
            Map<String, Object> dia = new LinkedHashMap<>();
            dia.put("data", dStr);
            dia.put("turnos", porDia.getOrDefault(dStr, Collections.emptyList()));
            dias.add(dia);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("dataInicio", data);
        result.put("dias", dias);
        return result;
    }

    // ── Helpers ──────────────────────────────────────────────

    private List<Map<String, Object>> agruparPorDia(List<Turno> turnos) {
        Map<LocalDate, List<Turno>> porDia = turnos.stream()
                .collect(Collectors.groupingBy(t -> t.getDataInicio().toLocalDate()));

        return porDia.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .map(entry -> {
                    Map<String, Object> dia = new LinkedHashMap<>();
                    dia.put("data", entry.getKey().toString());
                    dia.put("turnos", entry.getValue().stream()
                            .map(this::buildTurnoItem)
                            .collect(Collectors.toList()));
                    return dia;
                })
                .collect(Collectors.toList());
    }

    private Map<String, List<Map<String, Object>>> agruparPorDiaMap(List<Turno> turnos) {
        Map<String, List<Map<String, Object>>> result = new LinkedHashMap<>();
        for (Turno t : turnos) {
            String dStr = t.getDataInicio().toLocalDate().toString();
            result.computeIfAbsent(dStr, k -> new ArrayList<>()).add(buildTurnoItem(t));
        }
        return result;
    }

    private Map<String, Object> buildTurnoItem(Turno t) {
        DateTimeFormatter hm = DateTimeFormatter.ofPattern("HH:mm");

        Map<String, Object> item = new LinkedHashMap<>();
        item.put("id", t.getId());
        item.put("titulo", t.getTitulo());
        item.put("horarioInicio", t.getDataInicio().format(hm));
        item.put("horarioFim", t.getDataFim().format(hm));
        item.put("status", t.getStatus());
        item.put("raioKm", t.getRaioEntregaKm());
        item.put("valorEstimado", t.getValorEstimado());
        return item;
    }
}
