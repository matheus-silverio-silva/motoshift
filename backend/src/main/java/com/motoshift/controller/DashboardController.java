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

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
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
    private final com.motoshift.service.CarteiraService carteiraService;

    public DashboardController(UsuarioRepository usuarioRepo,
                               TurnoRepository turnoRepo,
                               CarteiraRepository carteiraRepo,
                               com.motoshift.service.CarteiraService carteiraService) {
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
        this.carteiraService = carteiraService;
    }

    @Operation(summary = "Dashboard do Lojista",
               description = "Retorna turnosAtivos, turnosFinalizados, turnosMes, totalGasto, "
                           + "avaliacaoMedia (nota média recebida pelo lojista) e "
                           + "reputacaoEntregadores (score médio dos motoboys que o atenderam) (RF02).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Métricas do lojista"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/lojista/{id}")
    public Map<String, Object> dashboardLojista(@PathVariable Long id) {
        com.motoshift.entity.Usuario lojista = usuarioRepo.findById(id)
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

        // Avaliação do próprio lojista: média das notas que ele recebeu,
        // mantida por AvaliacaoController.atualizarMedia().
        //
        // Antes este campo devolvia a média do `score` dos MOTOBOYS que
        // trabalharam para o lojista — dado de terceiros, num painel que o
        // lojista lê como sendo sobre ele. Além disso misturava dois
        // conceitos: `score` é reputação (começa em 5.0 e cai a cada
        // cancelamento tardio, RF07), não é avaliação.
        double avaliacaoMedia = lojista.getMediaAvaliacao() != null
                ? lojista.getMediaAvaliacao()
                : 0.0;

        // Reputação média dos entregadores que atenderam este lojista.
        // Continua sendo útil, mas agora com nome próprio.
        OptionalDouble mediaOpt = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()) && t.getMotoboyId() != null)
                .map(t -> usuarioRepo.findById(t.getMotoboyId()))
                .filter(java.util.Optional::isPresent)
                .map(java.util.Optional::get)
                .mapToDouble(u -> u.getScore() != null ? u.getScore() : 0.0)
                .average();
        double reputacaoEntregadores = mediaOpt.isPresent()
                ? Math.round(mediaOpt.getAsDouble() * 10.0) / 10.0
                : 0.0;

        List<TurnoResponse> turnosRecentes = todosTurnos.stream()
                .sorted((a, b) -> b.getCriadoEm().compareTo(a.getCriadoEm()))
                .limit(10)
                .map(TurnoResponse::from)
                .collect(Collectors.toList());

        BigDecimal totalGasto = todosTurnos.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .map(com.motoshift.entity.Turno::getValorEstimado)
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .setScale(2, RoundingMode.HALF_UP);

        Map<String, Object> resp = new HashMap<>();
        resp.put("turnosAtivos", turnosAtivos);
        resp.put("turnosFinalizados", turnosFinalizados);
        resp.put("turnosMes", turnosMes);
        resp.put("avaliacaoMedia", avaliacaoMedia);
        resp.put("reputacaoEntregadores", reputacaoEntregadores);
        resp.put("totalGasto", totalGasto);
        resp.put("turnosRecentes", turnosRecentes);
        return resp;
    }

    @Operation(summary = "Dashboard do Motoboy",
               description = "Retorna score (reputação), mediaAvaliacao (notas recebidas), saldoAtual, "
                           + "ganhosMensais, turnosAceitos, turnosFinalizados e turnosFinalizadosMes (RF02).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Métricas do motoboy"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/motoboy/{id}")
    public Map<String, Object> dashboardMotoboy(@PathVariable Long id) {
        Usuario motoboy = usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        Carteira carteira = carteiraRepo.findByUsuarioId(id).orElse(null);
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
        // Duas métricas distintas, expostas com nomes distintos:
        //   score          — reputação (5.0 inicial, penalizada por cancelamento tardio)
        //   mediaAvaliacao — média das notas recebidas de lojistas
        // Null quando o motoboy ainda não foi avaliado: a UI mostra "N/D" em
        // vez de fingir uma nota que ninguém deu.
        resp.put("score", java.util.Objects.requireNonNullElse(motoboy.getScore(), 5.0));
        resp.put("mediaAvaliacao", motoboy.getMediaAvaliacao());
        if (carteira != null) {
            // saldoAtual e mantido espelhando o disponivel: o app em producao le
            // esse nome. saldoBloqueado e novo e vem ao lado.
            resp.put("saldoAtual",      carteira.getSaldoDisponivel().setScale(2, RoundingMode.HALF_UP));
            resp.put("saldoDisponivel", carteira.getSaldoDisponivel().setScale(2, RoundingMode.HALF_UP));
            resp.put("saldoBloqueado",  carteira.getSaldoBloqueado().setScale(2, RoundingMode.HALF_UP));
        } else {
            resp.put("saldoAtual",      BigDecimal.ZERO.setScale(2));
            resp.put("saldoDisponivel", BigDecimal.ZERO.setScale(2));
            resp.put("saldoBloqueado",  BigDecimal.ZERO.setScale(2));
        }
        // Somado das transacoes do mes, nao mais de um contador na carteira.
        resp.put("ganhosMensais", carteiraService.ganhosDoMes(id));
        resp.put("turnosAceitos", turnosAceitos);
        resp.put("turnosFinalizados", turnosFinalizados);
        resp.put("turnosFinalizadosMes", turnosFinalizadosMes);
        return resp;
    }
}
