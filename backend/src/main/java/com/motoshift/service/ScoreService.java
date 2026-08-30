package com.motoshift.service;

import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Analise do score do entregador: as metricas dos ultimos 30 dias mais a
 * leitura que a IA faz delas.
 *
 * Estava inteira dentro do controller — a janela de 30 dias, a definicao de
 * cancelamento tardio, a estimativa do score anterior, as faixas de
 * classificacao e o prompt. Sao regras de negocio do MotoShift, e a primeira
 * pergunta de quem revisa e "onde ficam as regras de score?": a resposta agora
 * e um arquivo, e nao um endpoint.
 */
@Service
public class ScoreService {

    private static final int JANELA_DIAS = 30;

    /** Penalidade por cancelar com menos de 1h de antecedencia (RF07). */
    private static final double PENALIDADE_CANCELAMENTO_TARDIO = 0.5;

    private static final DateTimeFormatter DIA_MES_ANO =
            DateTimeFormatter.ofPattern("dd/MM/yyyy");

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final AnthropicService anthropic;

    public ScoreService(TurnoRepository turnoRepo,
                        UsuarioRepository usuarioRepo,
                        AnthropicService anthropic) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.anthropic = anthropic;
    }

    public Map<String, Object> analisar(Long motoboyId) {
        Usuario motoboy = usuarioRepo.findById(motoboyId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Motoboy não encontrado."));

        if (!"motoboy".equals(motoboy.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Endpoint exclusivo para perfil motoboy.");
        }

        double scoreAtual = motoboy.getScore() != null ? motoboy.getScore() : 5.0;
        LocalDateTime inicio30d = LocalDateTime.now().minusDays(JANELA_DIAS);

        List<Turno> todosTurnos = turnoRepo.findByMotoboyId(motoboyId);

        // Cancelamentos tardios na janela: cancelou com menos de 1h de
        // antecedencia, que e o unico evento que mexe no score hoje.
        List<Turno> canceladosTardios30d = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.CANCELADO)
                .filter(t -> dentroDaJanela(t, inicio30d))
                .filter(this::cancelamentoTardio)
                .collect(Collectors.toList());

        // Estima o score de 30 dias atras revertendo as penalizacoes recentes.
        double scoreAnterior = Math.min(5.0,
                scoreAtual + canceladosTardios30d.size() * PENALIDADE_CANCELAMENTO_TARDIO);
        double variacao = Math.round((scoreAtual - scoreAnterior) * 10.0) / 10.0;
        String tendencia = variacao > 0 ? "up" : (variacao < 0 ? "down" : "stable");
        String classificacao = classificar(scoreAtual);

        long finalizados30d = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO)
                .filter(t -> dentroDaJanela(t, inicio30d))
                .count();

        long cancelados30d = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.CANCELADO)
                .filter(t -> dentroDaJanela(t, inicio30d))
                .count();

        String analise;
        try {
            analise = anthropic.chamarClaude(
                    AnthropicService.SYSTEM_PROMPT_SCORE,
                    montarPrompt(motoboy.getNome(), scoreAtual, scoreAnterior, variacao,
                            classificacao, finalizados30d, cancelados30d,
                            canceladosTardios30d.size()));
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Serviço de análise de score temporariamente indisponível. Tente novamente.");
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scoreAtual", scoreAtual);
        result.put("scoreAnterior", scoreAnterior);
        result.put("variacao", variacao);
        result.put("tendencia", tendencia);
        result.put("classificacao", classificacao);
        result.put("analise", analise);
        result.put("ultimaAtualizacao", LocalDate.now().format(DIA_MES_ANO));
        result.put("eventos", ultimosEventos(todosTurnos));
        return result;
    }

    private boolean dentroDaJanela(Turno t, LocalDateTime inicio) {
        return t.getDataInicio() != null && !t.getDataInicio().isBefore(inicio);
    }

    private boolean cancelamentoTardio(Turno t) {
        return t.getAtualizadoEm() != null
                && t.getDataInicio() != null
                && t.getAtualizadoEm().isAfter(t.getDataInicio().minusHours(1));
    }

    private String classificar(double score) {
        if (score >= 4.5) return "Excelente";
        if (score >= 3.5) return "Bom";
        if (score >= 2.5) return "Regular";
        return "Baixo";
    }

    /** Ultimos 10 eventos (finalizados + cancelados), do mais recente ao mais antigo. */
    private List<Map<String, Object>> ultimosEventos(List<Turno> todosTurnos) {
        return todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO || t.getStatus() == StatusTurno.CANCELADO)
                .filter(t -> t.getDataInicio() != null)
                .sorted(Comparator.comparing(Turno::getDataInicio).reversed())
                .limit(10)
                .map(t -> {
                    boolean tardio = t.getStatus() == StatusTurno.CANCELADO && cancelamentoTardio(t);
                    // Rotulo de evento que o app desenha, nao o status da
                    // entidade: "cancelado_tardio" nao existe como estado. Os
                    // outros dois saem do proprio enum para nao virarem duas
                    // verdades sobre a mesma palavra.
                    String tipo = t.getStatus() == StatusTurno.FINALIZADO
                            ? StatusTurno.FINALIZADO.getValor()
                            : (tardio ? "cancelado_tardio" : StatusTurno.CANCELADO.getValor());

                    Map<String, Object> ev = new HashMap<>();
                    ev.put("tipo", tipo);
                    ev.put("titulo", t.getTitulo());
                    ev.put("data", t.getDataInicio().format(DIA_MES_ANO));
                    ev.put("impacto", tardio ? -PENALIDADE_CANCELAMENTO_TARDIO : 0.0);
                    return ev;
                })
                .collect(Collectors.toList());
    }

    private String montarPrompt(String nome, double scoreAtual, double scoreAnterior,
                                double variacao, String classificacao,
                                long finalizados30d, long cancelados30d, int tardios30d) {
        return String.format(
                "Análise de score do motoboy nos últimos 30 dias:%n" +
                "- Nome: %s%n" +
                "- Score atual: %.2f/5.0%n" +
                "- Score estimado há 30 dias: %.2f/5.0%n" +
                "- Variação: %+.1f%n" +
                "- Classificação atual: %s%n" +
                "- Turnos concluídos nos últimos 30 dias: %d%n" +
                "- Turnos cancelados nos últimos 30 dias: %d%n" +
                "- Cancelamentos tardios (< 1h de antecedência, penalizam -0.5 cada): %d%n%n" +
                "Regras de score do MotoShift:%n" +
                "- Score inicial: 5.0%n" +
                "- Cancelamento com menos de 1h de antecedência: -0.5%n" +
                "- Concluir turnos: sem impacto direto no score%n%n" +
                "Forneça uma análise do score deste motoboy. Inclua:%n" +
                "1. Interpretação do score atual em 1-2 frases%n" +
                "2. O que está indo bem ou o que causou a variação%n" +
                "3. Uma dica prática para manter ou melhorar o score%n" +
                "Linguagem direta e encorajadora. Máximo 120 palavras.",
                nome, scoreAtual, scoreAnterior, variacao,
                classificacao, finalizados30d, cancelados30d, tardios30d);
    }
}
