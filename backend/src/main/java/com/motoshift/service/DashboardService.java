package com.motoshift.service;

import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.dto.TurnoResponse;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
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

/**
 * Indicadores das telas iniciais dos dois perfis (RF02).
 *
 * Sao contas de negocio — turnos ativos no mes, total gasto, reputacao media
 * dos entregadores que atenderam a loja, saldo e ganhos do entregador — que
 * estavam escritas dentro do controller. Aqui elas podem ser testadas sem subir
 * HTTP, e o controller volta a ser roteamento.
 */
@Service
public class DashboardService {

    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;
    private final CarteiraRepository carteiraRepo;
    private final CarteiraService carteiraService;

    public DashboardService(UsuarioRepository usuarioRepo,
                            TurnoRepository turnoRepo,
                            CarteiraRepository carteiraRepo,
                            CarteiraService carteiraService) {
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
        this.carteiraService = carteiraService;
    }

    public Map<String, Object> doLojista(Long id) {
        com.motoshift.entity.Usuario lojista = usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        List<com.motoshift.entity.Turno> todosTurnos = turnoRepo.findByLojistId(id);

        long turnosAtivos = turnoRepo.countByLojistIdAndStatusIn(id, List.of(StatusTurno.ABERTO, StatusTurno.ACEITO, StatusTurno.EM_ANDAMENTO));
        long turnosFinalizados = turnoRepo.countByLojistIdAndStatusIn(id, List.of(StatusTurno.FINALIZADO));

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
        //
        // Os scores vêm numa consulta só: o findById dentro do stream fazia uma
        // ida ao banco por turno finalizado do lojista.
        Map<Long, Double> scorePorEntregador = scoresDosEntregadores(todosTurnos);
        OptionalDouble mediaOpt = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO && t.getMotoboyId() != null)
                .filter(t -> scorePorEntregador.containsKey(t.getMotoboyId()))
                .mapToDouble(t -> scorePorEntregador.get(t.getMotoboyId()))
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
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO)
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

    /** Score de cada entregador que aparece na lista de turnos, numa consulta. */
    private Map<Long, Double> scoresDosEntregadores(List<com.motoshift.entity.Turno> turnos) {
        List<Long> ids = turnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO && t.getMotoboyId() != null)
                .map(com.motoshift.entity.Turno::getMotoboyId)
                .distinct()
                .toList();
        Map<Long, Double> scores = new HashMap<>();
        if (ids.isEmpty()) return scores;
        for (Usuario u : usuarioRepo.findAllById(ids)) {
            scores.put(u.getId(), u.getScore() != null ? u.getScore() : 0.0);
        }
        return scores;
    }

    public Map<String, Object> doMotoboy(Long id) {
        Usuario motoboy = usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        Carteira carteira = carteiraRepo.findByUsuarioId(id).orElse(null);
        List<com.motoshift.entity.Turno> todosTurnos = turnoRepo.findByMotoboyId(id);

        List<TurnoResponse> turnosAceitos = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.ACEITO || t.getStatus() == StatusTurno.EM_ANDAMENTO)
                .map(TurnoResponse::from)
                .collect(Collectors.toList());

        long turnosFinalizados = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO)
                .count();

        // Turnos finalizados no mês corrente
        LocalDateTime inicioMes = LocalDateTime.now()
                .withDayOfMonth(1).withHour(0).withMinute(0).withSecond(0).withNano(0);
        long turnosFinalizadosMes = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO
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
