package com.motoshift.controller;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.service.CarteiraService;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/carteira")
@CrossOrigin(origins = "*", allowedHeaders = "*")
public class CarteiraController {

    private final CarteiraService service;

    public CarteiraController(CarteiraService service) {
        this.service = service;
    }

    @GetMapping("/{motoboyId}")
    public CarteiraResponse buscar(@PathVariable Long motoboyId) {
        return service.buscar(motoboyId);
    }

    @PostMapping("/{motoboyId}/saque")
    public void saque(@PathVariable Long motoboyId, @RequestBody Map<String, Double> body) {
        service.saque(motoboyId, body.get("valor"));
    }
}
