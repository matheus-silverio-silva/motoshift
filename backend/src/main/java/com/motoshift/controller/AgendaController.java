package com.motoshift.controller;

import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.AgendaService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/agenda")
@Tag(name = "Agenda", description = "Calendário de turnos por mês ou semana")
public class AgendaController {

    private final AgendaService service;

    public AgendaController(AgendaService service) {
        this.service = service;
    }

    @Operation(summary = "Agenda mensal",
               description = "Retorna todos os turnos do mês agrupados por dia.")
    @GetMapping("/{usuarioId}")
    public Map<String, Object> agendaMensal(
            @PathVariable Long usuarioId,
            @RequestParam int mes,
            @RequestParam int ano,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(usuarioId);
        return service.mensal(usuarioId, mes, ano);
    }

    @Operation(summary = "Agenda semanal",
               description = "Retorna turnos dos 7 dias a partir da data informada.")
    @GetMapping("/{usuarioId}/semana")
    public Map<String, Object> agendaSemanal(
            @PathVariable Long usuarioId,
            @RequestParam String data,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(usuarioId);
        return service.semanal(usuarioId, data);
    }
}
