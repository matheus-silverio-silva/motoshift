package com.motoshift.controller;

import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.ScoreService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/score")
@Tag(name = "Score", description = "Análise de Score com Explicação por IA")
public class ScoreController {

    private final ScoreService service;

    public ScoreController(ScoreService service) {
        this.service = service;
    }

    @Operation(summary = "Análise de score do Motoboy",
               description = "Retorna análise detalhada do score via IA, com os eventos "
                           + "que mexeram nele. Exige o token do próprio motoboy.")
    @GetMapping("/{motoboyId}/analise")
    public Map<String, Object> analisarScore(
            @PathVariable Long motoboyId,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(motoboyId);
        return service.analisar(motoboyId);
    }
}
