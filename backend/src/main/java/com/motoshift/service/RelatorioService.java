package com.motoshift.service;

import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Relatorio mensal de motoboy e de lojista: apura os numeros do mes e pede a
 * leitura a IA.
 *
 * As 230 linhas de apuracao viviam no controller — melhor e pior dia, horario
 * de pico, taxa de cancelamento, antecedencia media de publicacao, comparativo
 * com o mes anterior. Nada disso e HTTP: e como o MotoShift mede o proprio
 * negocio, e e o tipo de conta que precisa ser conferida em um lugar so.
 */
@Service
public class RelatorioService {

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final AnthropicService anthropicService;

    public RelatorioService(TurnoRepository turnoRepo,
                            UsuarioRepository usuarioRepo,
                            AnthropicService anthropicService) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.anthropicService = anthropicService;
    }

    public Map<String, Object> doMotoboy(Long motoboyId) {
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

        BigDecimal ganhosAtual = somaValores(finalizados);
        BigDecimal mediaPorTurno = finalizados.isEmpty() ? BigDecimal.ZERO
                : ganhosAtual.divide(BigDecimal.valueOf(finalizados.size()), 2, RoundingMode.HALF_UP);

        // Melhor e pior dia por ganhos
        Map<String, BigDecimal> ganhosPorDia = finalizados.stream()
                .collect(Collectors.groupingBy(
                        t -> nomeDia(t.getDataInicio().getDayOfWeek()),
                        Collectors.reducing(BigDecimal.ZERO,
                                RelatorioService::valorOuZero,
                                BigDecimal::add)));

        String melhorDia = "Sem dados";
        BigDecimal melhorValor = BigDecimal.ZERO;
        String piorDia = "Sem dados";
        BigDecimal piorValor = BigDecimal.ZERO;
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
        BigDecimal ganhosAnterior = somaValores(finalizadosAnterior);
        String comparativo;
        if (ganhosAnterior.signum() == 0) {
            comparativo = ganhosAtual.signum() > 0 ? "primeiro mês com ganhos registrados" : "sem dados do mês anterior para comparar";
        } else {
            BigDecimal diferenca = ganhosAtual.subtract(ganhosAnterior);
            // Escala 4 antes de multiplicar por 100: dividir com escala 2 aqui
            // jogaria fora os centavos do percentual antes de virar porcentagem.
            BigDecimal pct = diferenca.divide(ganhosAnterior, 4, RoundingMode.HALF_UP)
                    .multiply(BigDecimal.valueOf(100));
            comparativo = pct.signum() >= 0
                    ? String.format("melhor em %.0f%% (R$ %.2f a mais)", pct, diferenca)
                    : String.format("pior em %.0f%% (R$ %.2f a menos)", pct.abs(), diferenca.abs());
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

    public Map<String, Object> doLojista(Long lojistaId) {

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

        BigDecimal totalGasto = somaValores(doMes.stream()
                .filter(t -> "finalizado".equals(t.getStatus()))
                .collect(Collectors.toList()));
        BigDecimal mediaPorTurno = totalPublicados > 0
                ? totalGasto.divide(BigDecimal.valueOf(totalPublicados), 2, RoundingMode.HALF_UP)
                : BigDecimal.ZERO;

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

    /** Valor do turno, com null tratado como zero — nunca propague null em conta. */
    private static BigDecimal valorOuZero(Turno t) {
        return t.getValorEstimado() == null ? BigDecimal.ZERO : t.getValorEstimado();
    }

    private static BigDecimal somaValores(List<Turno> turnos) {
        return turnos.stream()
                .map(RelatorioService::valorOuZero)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
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
