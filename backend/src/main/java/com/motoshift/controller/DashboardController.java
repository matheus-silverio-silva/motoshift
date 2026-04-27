package com.motoshift.controller;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.OptionalDouble;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/dashboard")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Dashboard", description = "Métricas e indicadores RF02")
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

    @Operation(summary = "Dashboard do Lojista",
               description = "Retorna turnosAtivos, turnosFinalizados, turnosMes, totalGasto e avaliacaoMedia (RF02).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Métricas do lojista"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/lojista/{id}")
    public Map<String, Object> dashboardLojista(@PathVariable Long id) {
        usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        List<com.motoshift.entity.Turno> todosTurnos = turnoRepo.findByLojistId(id);

        long turnosAtivos = turnoRepo.countByLojistIdAndStatusIn(id, List.of("aberto", "aceito", "em_andamento"));
        long turnosFinalizados = turnoRepo.countByLojistIdAndStatusIn(id, List.of("finalizado"));

        // Turnos publicados no mês corrente
        LocalDateTime inicioMes = LocalDateTime.now()
                .withDayOfMonth(1).withHour(0).withMinute(0).withSecond(0).withNano(0);
        long turnosMes = todosTurnos.stream()
                .filter(t -> t.getCriadoEm() != null && !t.getCriadoEm().isBefore(inicioMes))
                .count();

        // Avaliação média dos motoboys que trabalharam para este lojista
        OptionalDouble mediaOpt = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()) && t.getMotoboyId() != null)
                .map(t -> usuarioRepo.findById(t.getMotoboyId()))
                .filter(java.util.Optional::isPresent)
                .map(java.util.Optional::get)
                .mapToDouble(u -> u.getScore() != null ? u.getScore() : 0.0)
                .average();
        double avaliacaoMedia = mediaOpt.isPresent()
                ? Math.round(mediaOpt.getAsDouble() * 10.0) / 10.0
                : 0.0;

        List<TurnoResponse> turnosRecentes = todosTurnos.stream()
                .sorted((a, b) -> b.getCriadoEm().compareTo(a.getCriadoEm()))
                .limit(10)
                .map(TurnoResponse::from)
                .collect(Collectors.toList());

        double totalGasto = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .mapToDouble(t -> t.getValorEstimado() != null ? t.getValorEstimado() : 0)
                .sum();

        Map<String, Object> resp = new HashMap<>();
        resp.put("turnosAtivos", turnosAtivos);
        resp.put("turnosFinalizados", turnosFinalizados);
        resp.put("turnosMes", turnosMes);
        resp.put("avaliacaoMedia", avaliacaoMedia);
        resp.put("totalGasto", totalGasto);
        resp.put("turnosRecentes", turnosRecentes);
        return resp;
    }

    @Operation(summary = "Dashboard do Motoboy",
               description = "Retorna score, saldoAtual, ganhosMensais, turnosAceitos, turnosFinalizados e turnosFinalizadosMes (RF02).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Métricas do motoboy"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/motoboy/{id}")
    public Map<String, Object> dashboardMotoboy(@PathVariable Long id) {
        Usuario motoboy = usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        Carteira carteira = carteiraRepo.findByMotoboyId(id).orElse(null);
        List<com.motoshift.entity.Turno> todosTurnos = turnoRepo.findByMotoboyId(id);

        List<TurnoResponse> turnosAceitos = todosTurnos.stream()
                .filter(t -> "aceito".equals(t.getStatus()) || "em_andamento".equals(t.getStatus()))
                .map(TurnoResponse::from)
                .collect(Collectors.toList());

        long turnosFinalizados = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .count();

        // Turnos finalizados no mês corrente
        LocalDateTime inicioMes = LocalDateTime.now()
                .withDayOfMonth(1).withHour(0).withMinute(0).withSecond(0).withNano(0);
        long turnosFinalizadosMes = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus())
                        && t.getAtualizadoEm() != null
                        && !t.getAtualizadoEm().isBefore(inicioMes))
                .count();

        Map<String, Object> resp = new HashMap<>();
        resp.put("score", java.util.Objects.requireNonNullElse(motoboy.getScore(), 5.0));
        if (carteira != null) {
            resp.put("saldoAtual",    java.util.Objects.requireNonNullElse(carteira.getSaldoAtual(),    0.0));
            resp.put("ganhosMensais", java.util.Objects.requireNonNullElse(carteira.getGanhosMensais(), 0.0));
        } else {
            resp.put("saldoAtual",    0.0);
            resp.put("ganhosMensais", 0.0);
        }
        resp.put("turnosAceitos", turnosAceitos);
        resp.put("turnosFinalizados", turnosFinalizados);
        resp.put("turnosFinalizadosMes", turnosFinalizadosMes);
        return resp;
    }
}
