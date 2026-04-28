package com.motoshift.controller;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.service.CarteiraService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/carteira")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Carteira", description = "Saldo, saques e histórico financeiro do motoboy")
public class CarteiraController {

    private final CarteiraService service;

    public CarteiraController(CarteiraService service) {
        this.service = service;
    }

    @Operation(summary = "Consultar carteira", description = "Retorna saldo atual, ganhos mensais e histórico de transações.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Dados da carteira"),
        @ApiResponse(responseCode = "404", description = "Motoboy não encontrado")
    })
    @GetMapping("/{motoboyId}")
    public CarteiraResponse buscar(@PathVariable Long motoboyId) {
        return service.buscar(motoboyId);
    }

    @Operation(summary = "Solicitar saque", description = "Motoboy solicita retirada via Pix. Mínimo R$20,00 e chave Pix obrigatória.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Saque processado"),
        @ApiResponse(responseCode = "400", description = "Saldo insuficiente, mínimo não atingido ou sem chave Pix"),
        @ApiResponse(responseCode = "404", description = "Carteira não encontrada")
    })
    @PostMapping("/{motoboyId}/saque")
    public Map<String, Object> saque(@PathVariable Long motoboyId, @RequestBody Map<String, Double> body) {
        return service.saque(motoboyId, body.get("valor"));
    }

    @Operation(summary = "Atualizar chave Pix", description = "Cadastra ou atualiza a chave Pix para saques.")
    @ApiResponse(responseCode = "200", description = "Chave Pix atualizada")
    @PutMapping("/{motoboyId}/pix")
    public Map<String, String> atualizarPix(
            @PathVariable Long motoboyId,
            @RequestBody Map<String, String> body) {
        service.atualizarPix(motoboyId, body.get("chavePix"));
        return Map.of("mensagem", "Chave Pix atualizada com sucesso!");
    }

    @Operation(summary = "Gráfico de ganhos mensais", description = "Retorna ganhos por turno agrupados por mês (últimos N meses).")
    @ApiResponse(responseCode = "200", description = "Dados do gráfico")
    @GetMapping("/{motoboyId}/grafico")
    public List<Map<String, Object>> grafico(
            @PathVariable Long motoboyId,
            @RequestParam(defaultValue = "6") int meses) {
        return service.grafico(motoboyId, meses);
    }
}
