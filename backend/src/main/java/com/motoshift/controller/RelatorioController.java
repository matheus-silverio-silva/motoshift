package com.motoshift.controller;

import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.RelatorioService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/relatorio")
@Tag(name = "Relatório", description = "Relatório Financeiro Inteligente via IA (Motoboy e Lojista)")
public class RelatorioController {

    private final RelatorioService service;

    public RelatorioController(RelatorioService service) {
        this.service = service;
    }

    @Operation(summary = "Relatório financeiro do Motoboy",
               description = "Gera relatório personalizado via IA com base nos dados do mês atual. "
                           + "Exige o token do próprio motoboy.")
    @GetMapping("/motoboy/{motoboyId}")
    public Map<String, Object> relatorioMotoboy(
            @PathVariable Long motoboyId,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(motoboyId);
        return service.doMotoboy(motoboyId);
    }

    @Operation(summary = "Relatório operacional do Lojista",
               description = "Gera relatório personalizado via IA com base nos dados do mês atual. "
                           + "Exige o token do próprio lojista.")
    @GetMapping("/lojista/{lojistaId}")
    public Map<String, Object> relatorioLojista(
            @PathVariable Long lojistaId,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(lojistaId);
        return service.doLojista(lojistaId);
    }
}
