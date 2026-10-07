package com.motoshift.controller;

import com.motoshift.dto.DreResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.DreService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

/**
 * A DRE — o resultado do período, lucro ou prejuízo (RF13 / SCRUM-47).
 *
 * <p>Nenhuma rota recebe id de usuário nem papel: os dois saem do token
 * ({@link UsuarioAutenticado}). Não há "DRE de outra pessoa" a pedir, e o
 * papel decide qual das duas demonstrações é montada.
 */
@RestController
@RequestMapping("/api/financeiro/dre")
@Tag(name = "Resultado financeiro",
     description = "DRE simplificada (lucro ou prejuízo) e lançamentos gerenciais (RF13 / SCRUM-47)")
public class DreController {

    private final DreService service;

    public DreController(DreService service) {
        this.service = service;
    }

    @Operation(summary = "DRE do período",
               description = "Demonstração do resultado em regime de caixa: o que o extrato "
                       + "registrou mais o que o usuário informou. Devolve as linhas, o "
                       + "resultado, a situação (lucro, prejuizo ou equilibrio), os "
                       + "indicadores e a comparação com o período anterior de mesmo "
                       + "tamanho. Sem datas, o mês corrente. O papel vem do token.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "A DRE do período"),
        @ApiResponse(responseCode = "400", description = "Data final anterior à inicial")
    })
    @GetMapping
    public DreResponse dre(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataInicio,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataFim,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.dre(atual.id(), atual.tipo(), dataInicio, dataFim);
    }

    @Operation(summary = "DRE mês a mês",
               description = "Doze linhas do ano: receita, custos totais e resultado de cada "
                       + "mês, para o gráfico. Sem ano, o ano corrente.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Os doze meses"),
        @ApiResponse(responseCode = "400", description = "Ano fora do intervalo aceito")
    })
    @GetMapping("/mensal")
    public List<DreResponse.Mes> mensal(@RequestParam(required = false) Integer ano,
                                        @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.mensal(atual.id(), atual.tipo(), ano);
    }
}
