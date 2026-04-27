package com.motoshift.controller;

import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.AnthropicService;
import com.motoshift.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.DayOfWeek;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/relatorio")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Relatório", description = "Relatório Financeiro Inteligente via IA (Motoboy e Lojista)")
public class RelatorioController {

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final AnthropicService anthropicService;
    private final AuthService authService;

    public RelatorioController(TurnoRepository turnoRepo,
                               UsuarioRepository usuarioRepo,
                               AnthropicService anthropicService,
                               AuthService authService) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.anthropicService = anthropicService;
        this.authService = authService;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/relatorio/motoboy/{motoboyId}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Relatório financeiro do Motoboy",
               description = "Gera relatório personalizado via IA com base nos dados do mês atual. " +
                             "Requer token Bearer no header Authorization.")
    @GetMapping("/motoboy/{motoboyId}")
    public Map<String, Object> relatorioMotoboy(
            @PathVariable Long motoboyId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        Long tokenUserId = extrairEValidar(authHeader);
        if (!tokenUserId.equals(motoboyId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Acesso negado: você só pode acessar seu próprio relatório.");
        }

        Usuario motoboy = usuarioRepo.findById(motoboyId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Motoboy não encontrado."));
        if (!"motoboy".equals(motoboy.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Endpoint exclusivo para perfil motoboy.");
        }

        LocalDateTime now = LocalDateTime.now();
        LocalDateTime inicioMes = now.withDayOfMonth(1).withHour(0).withMinute(0).withSecond(0).withNano(0);
        LocalDateTime inicioMesAnterior = inicioMes.minusMonths(1);

        List<Turno> todos = turnoRepo.findByMotoboyId(motoboyId);

        List<Turno> doMes = todos.stream()
                .filter(t -> t.getDataInicio() != null && !t.getDataInicio().isBefore(inicioMes))
                .collect(Collectors.toList());

        List<Turno> finalizados = doMes.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .collect(Collectors.toList());

        List<Turno> cancelados = doMes.stream()
                .filter(t -> "cancelado".equals(t.getStatus()))
                .collect(Collectors.toList());

        List<Turno> finalizadosAnterior = todos.stream()
                .filter(t -> "finalizado".equals(t.getStatus())
                        && t.getDataInicio() != null
                        && !t.getDataInicio().isBefore(inicioMesAnterior)
                        && t.getDataInicio().isBefore(inicioMes))
                .collect(Collectors.toList());

        double ganhosAtual = finalizados.stream()
                .mapToDouble(t -> t.getValorEstimado() != null ? t.getValorEstimado() : 0).sum();
        double mediaPorTurno = !finalizados.isEmpty() ? ganhosAtual / finalizados.size() : 0;

        // Melhor e pior dia por ganhos
        Map<String, Double> ganhosPorDia = finalizados.stream()
                .collect(Collectors.groupingBy(
                        t -> nomeDia(t.getDataInicio().getDayOfWeek()),
                        Collectors.summingDouble(t -> t.getValorEstimado() != null ? t.getValorEstimado() : 0)));

        String melhorDia = "Sem dados";
        double melhorValor = 0;
        String piorDia = "Sem dados";
        double piorValor = 0;
        if (!ganhosPorDia.isEmpty()) {
            var maxEntry = ganhosPorDia.entrySet().stream().max(Map.Entry.comparingByValue()).get();
            var minEntry = ganhosPorDia.entrySet().stream().min(Map.Entry.comparingByValue()).get();
            melhorDia = maxEntry.getKey(); melhorValor = maxEntry.getValue();
            piorDia   = minEntry.getKey(); piorValor   = minEntry.getValue();
        }

        // Horário com mais turnos aceitos
        String horarioPico = finalizados.stream()
                .collect(Collectors.groupingBy(t -> t.getDataInicio().getHour(), Collectors.counting()))
                .entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .map(e -> String.format("%02dh - %02dh", e.getKey(), (e.getKey() + 1) % 24))
                .orElse("Sem dados");

        // Raio médio
        double raioMedio = finalizados.stream()
                .filter(t -> t.getRaioEntregaKm() != null)
                .mapToDouble(Turno::getRaioEntregaKm)
                .average().orElse(0);

        // Score
        double score = motoboy.getScore() != null ? motoboy.getScore() : 5.0;

        // Comparativo mês anterior
        double ganhosAnterior = finalizadosAnterior.stream()
                .mapToDouble(t -> t.getValorEstimado() != null ? t.getValorEstimado() : 0).sum();
        String comparativo;
        if (ganhosAnterior == 0) {
            comparativo = ganhosAtual > 0 ? "primeiro mês com ganhos registrados" : "sem dados do mês anterior para comparar";
        } else {
            double pct = ((ganhosAtual - ganhosAnterior) / ganhosAnterior) * 100;
            comparativo = pct >= 0
                    ? String.format("melhor em %.0f%% (R$ %.2f a mais)", pct, ganhosAtual - ganhosAnterior)
                    : String.format("pior em %.0f%% (R$ %.2f a menos)", Math.abs(pct), ganhosAnterior - ganhosAtual);
        }

        String contexto = String.format(
                "Dados financeiros do motoboy no mês atual:%n" +
                "- Nome: %s%n" +
                "- Total de turnos concluídos: %d%n" +
                "- Total de turnos cancelados: %d%n" +
                "- Ganhos totais brutos: R$ %.2f%n" +
                "- Média de ganho por turno: R$ %.2f%n" +
                "- Melhor dia da semana em ganhos: %s (R$ %.2f)%n" +
                "- Pior dia da semana em ganhos: %s (R$ %.2f)%n" +
                "- Horário com mais turnos aceitos: %s%n" +
                "- Raio médio de entrega aceito: %.1f km%n" +
                "- Score atual na plataforma: %.2f/5%n" +
                "- Comparativo com mês anterior: %s%n%n" +
                "Gere um relatório financeiro personalizado em linguagem simples e motivadora para este motoboy. Inclua:%n" +
                "1. Um resumo do mês em 2-3 frases%n" +
                "2. Seu ponto mais forte do mês%n" +
                "3. Uma oportunidade clara de ganhar mais no próximo mês%n" +
                "4. Uma dica prática baseada nos dados%n" +
                "Seja direto, use linguagem informal e positiva. Máximo 150 palavras.",
                motoboy.getNome(), finalizados.size(), cancelados.size(),
                ganhosAtual, mediaPorTurno,
                melhorDia, melhorValor, piorDia, piorValor,
                horarioPico, raioMedio, score, comparativo);

        return gerarResposta("motoboy", now, contexto, AnthropicService.SYSTEM_PROMPT_RELATORIO_MOTOBOY);
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/relatorio/lojista/{lojistaId}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Relatório operacional do Lojista",
               description = "Gera relatório personalizado via IA com base nos dados do mês atual. " +
                             "Requer token Bearer no header Authorization.")
    @GetMapping("/lojista/{lojistaId}")
    public Map<String, Object> relatorioLojista(
            @PathVariable Long lojistaId,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        Long tokenUserId = extrairEValidar(authHeader);
        if (!tokenUserId.equals(lojistaId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Acesso negado: você só pode acessar seu próprio relatório.");
        }

        Usuario lojista = usuarioRepo.findById(lojistaId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Lojista não encontrado."));
        if (!"lojista".equals(lojista.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Endpoint exclusivo para perfil lojista.");
        }

        LocalDateTime now = LocalDateTime.now();
        LocalDateTime inicioMes = now.withDayOfMonth(1).withHour(0).withMinute(0).withSecond(0).withNano(0);

        List<Turno> todos = turnoRepo.findByLojistId(lojistaId);
        List<Turno> doMes = todos.stream()
                .filter(t -> t.getCriadoEm() != null && !t.getCriadoEm().isBefore(inicioMes))
                .collect(Collectors.toList());

        int totalPublicados = doMes.size();
        long comMotoboy = doMes.stream().filter(t -> t.getMotoboyId() != null).count();
        long semCobertura = totalPublicados - comMotoboy;

        double totalGasto = doMes.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .mapToDouble(t -> t.getValorEstimado() != null ? t.getValorEstimado() : 0).sum();
        double mediaPorTurno = totalPublicados > 0 ? totalGasto / totalPublicados : 0;

        // Dia com maior demanda
        String diaMaiorDemanda = doMes.stream()
                .collect(Collectors.groupingBy(t -> nomeDia(t.getCriadoEm().getDayOfWeek()), Collectors.counting()))
                .entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .map(Map.Entry::getKey)
                .orElse("Sem dados");

        // Horário de pico de publicações
        String horarioPico = doMes.stream()
                .collect(Collectors.groupingBy(t -> t.getCriadoEm().getHour(), Collectors.counting()))
                .entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .map(e -> String.format("%02dh - %02dh", e.getKey(), (e.getKey() + 1) % 24))
                .orElse("Sem dados");

        // Taxa de cancelamento por motoboys
        long canceladosComMotoboy = doMes.stream()
                .filter(t -> t.getMotoboyId() != null && "cancelado".equals(t.getStatus())).count();
        double taxaCancelamento = comMotoboy > 0 ? (canceladosComMotoboy * 100.0 / comMotoboy) : 0;

        // Avaliação média dos motoboys que finalizaram turnos no mês
        OptionalDouble avaliacaoOpt = doMes.stream()
                .filter(t -> "finalizado".equals(t.getStatus()) && t.getMotoboyId() != null)
                .map(t -> usuarioRepo.findById(t.getMotoboyId()))
                .filter(Optional::isPresent)
                .mapToDouble(opt -> opt.get().getScore() != null ? opt.get().getScore() : 5.0)
                .average();
        double avaliacaoMedia = avaliacaoOpt.isPresent()
                ? Math.round(avaliacaoOpt.getAsDouble() * 10.0) / 10.0 : 0;

        // Antecedência média ao publicar turnos (horas entre criadoEm e dataInicio)
        double antecipacaoMedia = doMes.stream()
                .filter(t -> t.getCriadoEm() != null && t.getDataInicio() != null)
                .mapToLong(t -> ChronoUnit.HOURS.between(t.getCriadoEm(), t.getDataInicio()))
                .filter(h -> h >= 0)
                .average().orElse(0);

        String contexto = String.format(
                "Dados operacionais do lojista no mês atual:%n" +
                "- Nome do estabelecimento: %s%n" +
                "- Total de turnos publicados: %d%n" +
                "- Turnos com motoboy confirmado: %d%n" +
                "- Turnos sem cobertura (sem motoboy): %d%n" +
                "- Total gasto com frete: R$ %.2f%n" +
                "- Média de gasto por turno: R$ %.2f%n" +
                "- Dia com maior demanda de turnos: %s%n" +
                "- Horário de pico de publicações: %s%n" +
                "- Taxa de cancelamento de motoboys: %.1f%%%n" +
                "- Avaliação média dos motoboys: %.1f/5%n" +
                "- Antecedência média ao publicar turnos: %.1f horas%n%n" +
                "Gere um relatório operacional personalizado para este lojista. Inclua:%n" +
                "1. Resumo do mês em 2-3 frases%n" +
                "2. O que funcionou bem na operação de delivery%n" +
                "3. Principal problema operacional identificado nos dados%n" +
                "4. Uma recomendação prática para reduzir custos ou melhorar a cobertura de turnos%n" +
                "Linguagem profissional mas acessível. Máximo 150 palavras.",
                lojista.getNome(), totalPublicados, (int) comMotoboy, (int) semCobertura,
                totalGasto, mediaPorTurno, diaMaiorDemanda, horarioPico,
                taxaCancelamento, avaliacaoMedia, antecipacaoMedia);

        return gerarResposta("lojista", now, contexto, AnthropicService.SYSTEM_PROMPT_RELATORIO_LOJISTA);
    }

    // ─────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────

    private Map<String, Object> gerarResposta(String perfil, LocalDateTime now, String contexto, String systemPrompt) {
        String[] meses = {"Janeiro","Fevereiro","Março","Abril","Maio","Junho",
                          "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"};
        String periodo = meses[now.getMonthValue() - 1] + " " + now.getYear();

        try {
            String relatorio = anthropicService.chamarClaude(systemPrompt, contexto);
            Map<String, Object> result = new HashMap<>();
            result.put("periodo", periodo);
            result.put("perfil", perfil);
            result.put("relatorio", relatorio);
            return result;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Serviço de relatórios temporariamente indisponível. Tente novamente.");
        }
    }

    private Long extrairEValidar(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Token de autenticação obrigatório.");
        }
        return authService.validarToken(authHeader.substring(7));
    }

    private String nomeDia(DayOfWeek dia) {
        return switch (dia) {
            case MONDAY -> "Segunda";
            case TUESDAY -> "Terça";
            case WEDNESDAY -> "Quarta";
            case THURSDAY -> "Quinta";
            case FRIDAY -> "Sexta";
            case SATURDAY -> "Sábado";
            case SUNDAY -> "Domingo";
        };
    }
}
