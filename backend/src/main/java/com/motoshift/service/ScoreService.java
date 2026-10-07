package com.motoshift.service;

import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.Desistencia;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
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
 *
 * <p><b>O "cancelamento" do entregador e a desistencia.</b> Desde a V22 ele nao
 * cancela turno: desiste da vaga, e a desistencia mora na inscricao
 * ({@link Desistencia}). O turno que a LOJA cancelou nao e evento dele e nao
 * aparece aqui. Os rotulos de evento que o app desenha ("cancelado",
 * "cancelado_tardio") continuam os mesmos.
 */
@Service
public class ScoreService {

    private static final Logger log = LoggerFactory.getLogger(ScoreService.class);

    private static final int JANELA_DIAS = 30;

    /** Penalidade por desistir da vaga com menos de 1h de antecedencia (RF07). */
    private static final double PENALIDADE_CANCELAMENTO_TARDIO = Reputacao.PENALIDADE_CANCELAMENTO_TARDIO;

    private static final DateTimeFormatter DIA_MES_ANO =
            DateTimeFormatter.ofPattern("dd/MM/yyyy");

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final AnthropicService anthropic;
    private final Reputacao reputacao;

    public ScoreService(TurnoRepository turnoRepo,
                        TurnoInscricaoRepository inscricaoRepo,
                        UsuarioRepository usuarioRepo,
                        AnthropicService anthropic,
                        Reputacao reputacao) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.anthropic = anthropic;
        this.reputacao = reputacao;
    }

    public Map<String, Object> analisar(Long motoboyId) {
        Usuario motoboy = usuarioRepo.findById(motoboyId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Motoboy não encontrado."));

        if (!"motoboy".equals(motoboy.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Endpoint exclusivo para perfil motoboy.");
        }

        // Sem histórico não há reputação a analisar: o 5,0 é o ponto de partida
        // da conta, não uma nota. A resposta diz isso, sem chamar a IA para
        // comentar um número que nenhum evento produziu.
        Double visivel = reputacao.scoreVisivel(motoboy);
        if (visivel == null) {
            return semHistorico();
        }
        double scoreAtual = visivel;
        LocalDateTime inicio30d = LocalDateTime.now().minusDays(JANELA_DIAS);

        List<Turno> todosTurnos = turnoRepo.findByMotoboyId(motoboyId);
        List<Desistencia> desistencias = inscricaoRepo.desistenciasDe(motoboyId);

        // Desistencias em cima da hora na janela: saiu da vaga com menos de 1h
        // de antecedencia, que e o unico evento que mexe no score hoje.
        List<Desistencia> canceladosTardios30d = desistencias.stream()
                .filter(d -> dentroDaJanela(d.inicioDoTurno(), inicio30d))
                .filter(ScoreService::tardia)
                .collect(Collectors.toList());

        // ESTIMATIVA, nao medicao: nao existe historico de score no banco, entao
        // o valor de 30 dias atras e reconstruido revertendo as penalizacoes da
        // janela. Sai rotulado como estimado na resposta (scoreAnteriorEstimado)
        // para a tela nao apresentar conta como registro. Medir de verdade pede
        // uma tabela de eventos de score — e ela daria substancia a esta mesma
        // tela, hoje montada a partir dos turnos.
        double scoreAnterior = Math.min(Reputacao.SCORE_INICIAL,
                scoreAtual + canceladosTardios30d.size() * PENALIDADE_CANCELAMENTO_TARDIO);
        double variacao = Math.round((scoreAtual - scoreAnterior) * 10.0) / 10.0;
        String tendencia = variacao > 0 ? "up" : (variacao < 0 ? "down" : "stable");
        String classificacao = classificar(scoreAtual);

        long finalizados30d = todosTurnos.stream()
                .filter(t -> t.getStatus() == StatusTurno.FINALIZADO)
                .filter(t -> dentroDaJanela(t.getDataInicio(), inicio30d))
                .count();

        long cancelados30d = desistencias.stream()
                .filter(d -> dentroDaJanela(d.inicioDoTurno(), inicio30d))
                .count();

        // O endpoint inteiro caia com 503 quando a IA falhava — mesmo com todas
        // as metricas ja calculadas aqui, sem depender dela. Agora a IA e o que
        // ela sempre foi: um complemento. Se falhar, a tela mostra os numeros e
        // "analise indisponivel" no lugar do texto.
        String analise = null;
        try {
            analise = anthropic.chamarClaude(
                    AnthropicService.SYSTEM_PROMPT_SCORE,
                    montarPrompt(motoboy.getNome(), scoreAtual, scoreAnterior, variacao,
                            classificacao, finalizados30d, cancelados30d,
                            canceladosTardios30d.size()));
        } catch (RuntimeException e) {
            log.warn("[score] analise da IA indisponivel para o motoboy {}: {}",
                    motoboyId, e.getMessage());
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scoreAtual", scoreAtual);
        result.put("scoreAnterior", scoreAnterior);
        // O app precisa saber que este numero e conta, nao medicao.
        result.put("scoreAnteriorEstimado", true);
        result.put("variacao", variacao);
        result.put("tendencia", tendencia);
        result.put("classificacao", classificacao);
        result.put("analise", analise);
        result.put("analiseDisponivel", analise != null);
        result.put("ultimaAtualizacao", LocalDate.now().format(DIA_MES_ANO));
        result.put("eventos", ultimosEventos(todosTurnos, desistencias));
        result.put("novoNaPlataforma", false);
        return result;
    }

    /** A análise de quem ainda não tem turno concluído nem cancelado. */
    private Map<String, Object> semHistorico() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scoreAtual", null);
        result.put("novoNaPlataforma", true);
        result.put("classificacao", "Novo na plataforma");
        result.put("analise", null);
        result.put("analiseDisponivel", false);
        result.put("ultimaAtualizacao", LocalDate.now().format(DIA_MES_ANO));
        result.put("eventos", List.of());
        return result;
    }

    private static boolean dentroDaJanela(LocalDateTime inicioDoTurno, LocalDateTime inicio) {
        return inicioDoTurno != null && !inicioDoTurno.isBefore(inicio);
    }

    /** Desistiu em cima da hora — a mesma pergunta que o TurnoService faz para penalizar. */
    private static boolean tardia(Desistencia d) {
        return Reputacao.emCimaDaHora(d.canceladoEm(), d.inicioDoTurno());
    }

    private String classificar(double score) {
        if (score >= 4.5) return "Excelente";
        if (score >= 3.5) return "Bom";
        if (score >= 2.5) return "Regular";
        return "Baixo";
    }

    /** Um evento da lista, antes de virar o mapa que a tela recebe. */
    private record Evento(String tipo, String titulo, LocalDateTime inicioDoTurno, double impacto) {}

    /** Ultimos 10 eventos (turnos concluidos + desistencias), do mais recente ao mais antigo. */
    private List<Map<String, Object>> ultimosEventos(List<Turno> todosTurnos,
                                                    List<Desistencia> desistencias) {
        List<Evento> eventos = new ArrayList<>();
        for (Turno t : todosTurnos) {
            if (t.getStatus() != StatusTurno.FINALIZADO || t.getDataInicio() == null) continue;
            eventos.add(new Evento(StatusTurno.FINALIZADO.getValor(), t.getTitulo(),
                    t.getDataInicio(), 0.0));
        }
        for (Desistencia d : desistencias) {
            if (d.inicioDoTurno() == null) continue;
            boolean tardio = tardia(d);
            // Rotulo de evento que o app desenha, nao o status da entidade:
            // "cancelado_tardio" nao existe como estado. O outro sai do proprio
            // enum para nao virarem duas verdades sobre a mesma palavra.
            eventos.add(new Evento(
                    tardio ? "cancelado_tardio" : StatusTurno.CANCELADO.getValor(),
                    d.titulo(), d.inicioDoTurno(),
                    tardio ? -PENALIDADE_CANCELAMENTO_TARDIO : 0.0));
        }
        return eventos.stream()
                .sorted(Comparator.comparing(Evento::inicioDoTurno).reversed())
                .limit(10)
                .map(e -> {
                    Map<String, Object> ev = new HashMap<>();
                    ev.put("tipo", e.tipo());
                    ev.put("titulo", e.titulo());
                    ev.put("data", e.inicioDoTurno().format(DIA_MES_ANO));
                    ev.put("impacto", e.impacto());
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
                "- Vagas de que desistiu nos últimos 30 dias: %d%n" +
                "- Desistências em cima da hora (< 1h de antecedência, penalizam -0.5 cada): %d%n%n" +
                "Regras de score do MotoShift:%n" +
                "- Score inicial: 5.0%n" +
                "- Desistir da vaga com menos de 1h de antecedência: -0.5%n" +
                "- Turno cancelado pela loja ou falta sem check-in: sem impacto no score%n" +
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
