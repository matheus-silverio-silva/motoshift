package com.motoshift.controller;

import com.motoshift.dto.GorjetaRequest;
import com.motoshift.dto.GorjetaResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.GorjetaService;
import com.motoshift.service.ledger.RetentativaOtimista;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/turnos/{turnoId}/gorjetas")
@Tag(name = "Gorjetas", description = "Gorjeta do lojista ao entregador, depois do turno")
public class GorjetaController {

    private final GorjetaService gorjetas;

    /** A gorjeta move dinheiro: o retry otimista mora em quem abre a transação. */
    private final RetentativaOtimista retentativa;

    public GorjetaController(GorjetaService gorjetas, RetentativaOtimista retentativa) {
        this.gorjetas = gorjetas;
        this.retentativa = retentativa;
    }

    @Operation(summary = "Dar gorjeta",
            description = "Só o lojista do turno, com o turno finalizado, a quem trabalhou nele; "
                    + "uma por entregador por turno, até motoshift.gorjeta.maximo (padrão R$ 50), "
                    + "com saldo disponível. Repetir a mesma gorjeta não cobra de novo.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Gorjeta dada (ou já estava)"),
        @ApiResponse(responseCode = "400", description = "Valor fora do permitido"),
        @ApiResponse(responseCode = "403", description = "Não é o lojista do turno"),
        @ApiResponse(responseCode = "409", description = "Turno não finalizado, ou já houve gorjeta de outro valor"),
        @ApiResponse(responseCode = "422", description = "Entregador não trabalhou no turno, ou saldo insuficiente")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public GorjetaResponse dar(@PathVariable Long turnoId,
                               @Valid @RequestBody GorjetaRequest req,
                               @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("lojista");
        return retentativa.executar("dar gorjeta",
                () -> gorjetas.dar(turnoId, atual.id(), req.entregadorId(), req.valor()));
    }

    @Operation(summary = "Gorjetas do turno",
            description = "O lojista vê todas; o entregador, só a dele.")
    @GetMapping
    public List<GorjetaResponse> doTurno(@PathVariable Long turnoId,
                                         @AuthenticationPrincipal UsuarioAutenticado atual) {
        return gorjetas.doTurno(turnoId, atual.id());
    }
}
