package com.motoshift.service;

import com.motoshift.entity.Turno;
import com.motoshift.repository.TurnoRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Calendario de turnos: mes e semana, agrupados por dia.
 *
 * O agrupamento e a montagem do item de calendario saem do controller. Sao
 * dois formatos de resposta com regra propria — a semana precisa devolver os
 * sete dias mesmo vazios, o mes so devolve os dias com turno — e isso e
 * decisao de produto, nao de transporte.
 */
@Service
public class AgendaService {

    private static final DateTimeFormatter HORA_MINUTO = DateTimeFormatter.ofPattern("HH:mm");

    private final TurnoRepository turnoRepo;

    public AgendaService(TurnoRepository turnoRepo) {
        this.turnoRepo = turnoRepo;
    }

    public Map<String, Object> mensal(Long usuarioId, int mes, int ano) {
        LocalDateTime inicio = LocalDateTime.of(ano, mes, 1, 0, 0);
        LocalDateTime fim    = inicio.plusMonths(1);

        List<Turno> turnos = turnoRepo.findByUsuarioAndPeriodo(usuarioId, inicio, fim);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("mes", mes);
        result.put("ano", ano);
        result.put("dias", agruparPorDia(turnos));
        return result;
    }

    public Map<String, Object> semanal(Long usuarioId, String data) {
        LocalDate  dataBase = LocalDate.parse(data);
        LocalDateTime inicio = dataBase.atStartOfDay();
        LocalDateTime fim    = inicio.plusDays(7);

        List<Turno> turnos = turnoRepo.findByUsuarioAndPeriodo(usuarioId, inicio, fim);

        // Agrupa por dia e garante que todos os 7 dias aparecam, inclusive os
        // vazios: a tela desenha a semana inteira.
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
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("id", t.getId());
        item.put("titulo", t.getTitulo());
        item.put("horarioInicio", t.getDataInicio().format(HORA_MINUTO));
        item.put("horarioFim", t.getDataFim().format(HORA_MINUTO));
        item.put("status", t.getStatus());
        item.put("raioKm", t.getRaioEntregaKm());
        item.put("valorEstimado", t.getValorEstimado());
        return item;
    }
}
