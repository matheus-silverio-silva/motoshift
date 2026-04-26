package com.motoshift.controller;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/dashboard")
@CrossOrigin(origins = "*", allowedHeaders = "*")
public class DashboardController {

    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;
    private final CarteiraRepository carteiraRepo;

    public DashboardController(UsuarioRepository usuarioRepo,
                               TurnoRepository turnoRepo,
                               CarteiraRepository carteiraRepo) {
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
    }

    // RF02 — Dashboard do Lojista
    @GetMapping("/lojista/{id}")
    public Map<String, Object> dashboardLojista(@PathVariable Long id) {
        usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        long turnosAtivos = turnoRepo.countByLojistIdAndStatusIn(id, List.of("aberto", "aceito", "em_andamento"));
        long turnosFinalizados = turnoRepo.countByLojistIdAndStatusIn(id, List.of("finalizado"));

        List<TurnoResponse> turnosRecentes = turnoRepo.findByLojistId(id).stream()
                .sorted((a, b) -> b.getCriadoEm().compareTo(a.getCriadoEm()))
                .limit(10)
                .map(TurnoResponse::from)
                .collect(Collectors.toList());

        double totalGasto = turnoRepo.findByLojistId(id).stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .mapToDouble(t -> t.getValorEstimado() != null ? t.getValorEstimado() : 0)
                .sum();

        Map<String, Object> resp = new HashMap<>();
        resp.put("turnosAtivos", turnosAtivos);
        resp.put("turnosFinalizados", turnosFinalizados);
        resp.put("totalGasto", totalGasto);
        resp.put("turnosRecentes", turnosRecentes);
        return resp;
    }

    // RF02 — Dashboard do Motoboy
    @GetMapping("/motoboy/{id}")
    public Map<String, Object> dashboardMotoboy(@PathVariable Long id) {
        Usuario motoboy = usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        Carteira carteira = carteiraRepo.findByMotoboyId(id).orElse(null);

        List<TurnoResponse> turnosAceitos = turnoRepo.findByMotoboyId(id).stream()
                .filter(t -> "aceito".equals(t.getStatus()) || "em_andamento".equals(t.getStatus()))
                .map(TurnoResponse::from)
                .collect(Collectors.toList());

        long turnosFinalizados = turnoRepo.findByMotoboyId(id).stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .count();

        Map<String, Object> resp = new HashMap<>();
        resp.put("score", motoboy.getScore());
        resp.put("saldoAtual", carteira != null ? carteira.getSaldoAtual() : 0.0);
        resp.put("ganhosMensais", carteira != null ? carteira.getGanhosMensais() : 0.0);
        resp.put("turnosAceitos", turnosAceitos);
        resp.put("turnosFinalizados", turnosFinalizados);
        return resp;
    }
}
