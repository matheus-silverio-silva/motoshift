package com.motoshift.controller;

import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.DashboardService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/dashboard")
@Tag(name = "Dashboard", description = "Métricas e indicadores RF02")
public class DashboardController {

    private final DashboardService service;

    public DashboardController(DashboardService service) {
        this.service = service;
    }

    @Operation(summary = "Dashboard do Lojista",
               description = "Retorna turnosAtivos, turnosFinalizados, turnosMes, totalGasto, "
                           + "avaliacaoMedia (nota média recebida pelo lojista) e "
                           + "reputacaoEntregadores (score médio dos motoboys que o atenderam) (RF02).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Métricas do lojista"),
        @ApiResponse(responseCode = "403", description = "Dashboard de outro usuário"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/lojista/{id}")
    public Map<String, Object> dashboardLojista(@PathVariable Long id,
                                                @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(id);
        return service.doLojista(id);
    }

    @Operation(summary = "Dashboard do Motoboy",
               description = "Retorna saldo, ganhos do mês, turnos aceitos e finalizados (RF02).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Métricas do motoboy"),
        @ApiResponse(responseCode = "403", description = "Dashboard de outro usuário"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/motoboy/{id}")
    public Map<String, Object> dashboardMotoboy(@PathVariable Long id,
                                                @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(id);
        return service.doMotoboy(id);
    }
}
