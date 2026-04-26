package com.motoshift.controller;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.service.TurnoService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/turnos")
@CrossOrigin(origins = "*", allowedHeaders = "*")
public class TurnoController {

    private final TurnoService service;

    public TurnoController(TurnoService service) {
        this.service = service;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TurnoResponse criar(@Valid @RequestBody TurnoRequest req) {
        return service.criar(req);
    }

    @GetMapping
    public List<TurnoResponse> listar(
            @RequestParam(required = false) Long lojistId,
            @RequestParam(required = false) Long motoboyId) {
        if (lojistId != null) return service.listarPorLojista(lojistId);
        if (motoboyId != null) return service.listarPorMotoboy(motoboyId);
        return service.listarDisponiveis();
    }

    @GetMapping("/disponiveis")
    public List<TurnoResponse> disponiveis() {
        return service.listarDisponiveis();
    }

    @GetMapping("/{id}")
    public TurnoResponse buscar(@PathVariable Long id) {
        return service.buscarPorId(id);
    }

    @PutMapping("/{id}/aceitar")
    public TurnoResponse aceitar(@PathVariable Long id, @RequestBody Map<String, Long> body) {
        return service.aceitar(id, body.get("motoboyId"));
    }

    @PutMapping("/{id}/finalizar")
    public TurnoResponse finalizar(@PathVariable Long id) {
        return service.finalizar(id);
    }

    @PutMapping("/{id}/cancelar")
    public TurnoResponse cancelar(@PathVariable Long id) {
        return service.cancelar(id);
    }
}
