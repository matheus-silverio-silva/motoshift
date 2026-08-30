package com.motoshift.controller;

import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.SugestaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/sugestoes")
@Tag(name = "Sugestões", description = "Sugestão inteligente de turnos via IA (Anthropic)")
public class SugestaoController {

    private final SugestaoService service;

    public SugestaoController(SugestaoService service) {
        this.service = service;
    }

    @Operation(
        summary = "Sugerir turnos para o motoboy",
        description = "Analisa o histórico dos últimos 30 dias e os turnos disponíveis. " +
                      "Retorna sugestão textual gerada pelo Claude (Anthropic)."
    )
    @GetMapping("/turnos/{motoboyId}")
    public Map<String, String> sugerirTurnos(@PathVariable Long motoboyId,
                                             @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(motoboyId);
        return service.sugerirPara(motoboyId);
    }
}
