package com.motoshift.controller;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.service.CarteiraService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/carteira")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Carteira", description = "Saldo, saques e histórico financeiro do usuário")
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
    @GetMapping("/{usuarioId}")
    public CarteiraResponse buscar(@PathVariable Long usuarioId) {
        return service.buscar(usuarioId);
    }

    @Operation(summary = "Solicitar saque", description = "Motoboy solicita retirada via Pix. Mínimo R$20,00 e chave Pix obrigatória.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Saque processado"),
        @ApiResponse(responseCode = "400", description = "Saldo insuficiente, mínimo não atingido ou sem chave Pix"),
        @ApiResponse(responseCode = "404", description = "Carteira não encontrada")
    })
    @PostMapping("/{usuarioId}/saque")
    public Map<String, Object> saque(@PathVariable Long usuarioId, @RequestBody Map<String, BigDecimal> body) {
        return service.saque(usuarioId, body.get("valor"));
    }

    @Operation(summary = "Atualizar chave Pix", description = "Cadastra ou atualiza a chave Pix para saques.")
    @ApiResponse(responseCode = "200", description = "Chave Pix atualizada")
    @PutMapping("/{usuarioId}/pix")
    public Map<String, String> atualizarPix(
            @PathVariable Long usuarioId,
            @RequestBody Map<String, String> body) {
        service.atualizarPix(usuarioId, body.get("chavePix"));
        return Map.of("mensagem", "Chave Pix atualizada com sucesso!");
    }

    @Operation(summary = "Gráfico de ganhos mensais", description = "Retorna ganhos por turno agrupados por mês (últimos N meses).")
    @ApiResponse(responseCode = "200", description = "Dados do gráfico")
    @GetMapping("/{usuarioId}/grafico")
    public List<Map<String, Object>> grafico(
            @PathVariable Long usuarioId,
            @RequestParam(defaultValue = "6") int meses) {
        return service.grafico(usuarioId, meses);
    }
}
