package com.motoshift.controller;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.service.CarteiraService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/carteira")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Carteira", description = "Saldo e saques do motoboy")
public class CarteiraController {

    private final CarteiraService service;

    public CarteiraController(CarteiraService service) {
        this.service = service;
    }

    @Operation(summary = "Consultar carteira", description = "Retorna saldo atual e ganhos mensais do motoboy.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Dados da carteira"),
        @ApiResponse(responseCode = "404", description = "Motoboy não encontrado")
    })
    @GetMapping("/{motoboyId}")
    public CarteiraResponse buscar(@PathVariable Long motoboyId) {
        return service.buscar(motoboyId);
    }

    @Operation(summary = "Solicitar saque", description = "Motoboy solicita retirada do saldo disponível.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Saque processado"),
        @ApiResponse(responseCode = "400", description = "Saldo insuficiente ou valor inválido"),
        @ApiResponse(responseCode = "404", description = "Carteira não encontrada")
    })
    @PostMapping("/{motoboyId}/saque")
    public void saque(@PathVariable Long motoboyId, @RequestBody Map<String, Double> body) {
        service.saque(motoboyId, body.get("valor"));
    }
}
