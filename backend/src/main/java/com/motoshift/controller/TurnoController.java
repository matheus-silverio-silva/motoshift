package com.motoshift.controller;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.service.TurnoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/turnos")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Turnos", description = "Gerenciamento de turnos de entrega (RF04-RF07)")
public class TurnoController {

    private final TurnoService service;

    public TurnoController(TurnoService service) {
        this.service = service;
    }

    @Operation(summary = "Publicar turno", description = "Lojista cria turno com antecedência mínima de 2h (RF04).")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Turno criado"),
        @ApiResponse(responseCode = "400", description = "Antecedência insuficiente ou dados inválidos")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TurnoResponse criar(@Valid @RequestBody TurnoRequest req) {
        return service.criar(req);
    }

    @Operation(summary = "Listar turnos", description = "Filtra por lojistId, motoboyId ou retorna todos disponíveis.")
    @ApiResponse(responseCode = "200", description = "Lista de turnos")
    @GetMapping
    public List<TurnoResponse> listar(
            @RequestParam(required = false) Long lojistId,
            @RequestParam(required = false) Long motoboyId) {
        if (lojistId != null) return service.listarPorLojista(lojistId);
        if (motoboyId != null) return service.listarPorMotoboy(motoboyId);
        return service.listarDisponiveis();
    }

    @Operation(summary = "Listar turnos disponíveis", description = "Retorna todos os turnos com status 'aberto'.")
    @ApiResponse(responseCode = "200", description = "Turnos disponíveis")
    @GetMapping("/disponiveis")
    public List<TurnoResponse> disponiveis() {
        return service.listarDisponiveis();
    }

    @Operation(summary = "Buscar turno por ID")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno encontrado"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado")
    })
    @GetMapping("/{id}")
    public TurnoResponse buscar(@PathVariable Long id) {
        return service.buscarPorId(id);
    }

    @Operation(summary = "Aceitar turno", description = "Motoboy aceita turno disponível. Valida conflito de agenda (RF05).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno aceito"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno indisponível ou conflito de horário")
    })
    @PutMapping("/{id}/aceitar")
    public TurnoResponse aceitar(@PathVariable Long id, @RequestBody Map<String, Long> body) {
        return service.aceitar(id, body.get("motoboyId"));
    }

    @Operation(summary = "Finalizar turno", description = "Marca turno como finalizado e credita valor na carteira (RF06).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno finalizado"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno já encerrado")
    })
    @PutMapping("/{id}/finalizar")
    public TurnoResponse finalizar(@PathVariable Long id) {
        return service.finalizar(id);
    }

    @Operation(summary = "Cancelar turno", description = "Cancela turno. Penaliza score do motoboy se < 1h antes do início (RF07).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno cancelado"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno já encerrado")
    })
    @PutMapping("/{id}/cancelar")
    public TurnoResponse cancelar(@PathVariable Long id) {
        return service.cancelar(id);
    }
}
