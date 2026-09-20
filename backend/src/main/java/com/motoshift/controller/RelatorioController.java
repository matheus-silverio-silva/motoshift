package com.motoshift.controller;

import com.motoshift.dto.RelatorioFinanceiroResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.RelatorioService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/relatorio")
@Tag(name = "Relatório", description = "Relatório Financeiro Inteligente via IA (Motoboy e Lojista)")
public class RelatorioController {

    private final RelatorioService service;

    public RelatorioController(RelatorioService service) {
        this.service = service;
    }

    @Operation(summary = "Relatório financeiro do entregador",
               description = "Apura os ganhos do período PELO EXTRATO — o que foi de fato pago, "
                       + "e não o valor que os turnos prometiam — e pede a leitura à IA. "
                       + "Se a IA não responder, os números vêm mesmo assim e 'analise' vem "
                       + "null: uma dependência externa opcional não derruba o relatório. "
                       + "Sem datas, apura o mês corrente. Exige o token do próprio entregador.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Números do período, com ou sem análise"),
        @ApiResponse(responseCode = "400", description = "Data final anterior à inicial"),
        @ApiResponse(responseCode = "403", description = "Perfil errado ou relatório de terceiro"),
        @ApiResponse(responseCode = "404", description = "Entregador não encontrado")
    })
    @GetMapping("/motoboy/{motoboyId}")
    public RelatorioFinanceiroResponse relatorioMotoboy(
            @PathVariable Long motoboyId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataInicio,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataFim,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(motoboyId);
        return service.doMotoboy(motoboyId, dataInicio, dataFim);
    }

    @Operation(summary = "Relatório operacional do lojista",
               description = "Apura o gasto do período PELO EXTRATO, com quebra por entregador, "
                       + "dia da semana e faixa de horário, mais recargas, reservas abertas e "
                       + "quanto voltou de turnos cancelados ou vencidos. Se a IA não "
                       + "responder, 'analise' vem null e os números permanecem. Sem datas, "
                       + "apura o mês corrente. Exige o token do próprio lojista.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Números do período, com ou sem análise"),
        @ApiResponse(responseCode = "400", description = "Data final anterior à inicial"),
        @ApiResponse(responseCode = "403", description = "Perfil errado ou relatório de terceiro"),
        @ApiResponse(responseCode = "404", description = "Lojista não encontrado")
    })
    @GetMapping("/lojista/{lojistaId}")
    public RelatorioFinanceiroResponse relatorioLojista(
            @PathVariable Long lojistaId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataInicio,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataFim,
            @AuthenticationPrincipal UsuarioAutenticado atual) {

        atual.exigirMesmoUsuario(lojistaId);
        return service.doLojista(lojistaId, dataInicio, dataFim);
    }
}
