package com.motoshift.controller;

import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/avaliacoes")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Avaliações", description = "Avaliação mútua entre lojistas e motoboys")
public class AvaliacaoController {

    private final AvaliacaoRepository avaliacaoRepo;
    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;

    public AvaliacaoController(AvaliacaoRepository avaliacaoRepo,
                                TurnoRepository turnoRepo,
                                UsuarioRepository usuarioRepo) {
        this.avaliacaoRepo = avaliacaoRepo;
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
    }

    // ─────────────────────────────────────────────────────────
    // POST /api/avaliacoes
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Registrar avaliação")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> avaliar(@RequestBody Map<String, Object> body) {
        Long turnoId     = toLong(body.get("turnoId"));
        Long avaliadorId = toLong(body.get("avaliadorId"));
        Long avaliadoId  = toLong(body.get("avaliadoId"));
        Integer nota     = (Integer) body.get("nota");
        String comentario = (String) body.get("comentario");

        // Valida turno
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado."));
        if (!"finalizado".equals(turno.getStatus())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Só é possível avaliar turnos finalizados.");
        }

        // Valida participação
        boolean participou = avaliadorId.equals(turno.getLojistId())
                || avaliadorId.equals(turno.getMotoboyId());
        if (!participou) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Avaliador não participou deste turno.");
        }

        // Valida duplicata
        if (avaliacaoRepo.existsByTurnoIdAndAvaliadorId(turnoId, avaliadorId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Você já avaliou este turno.");
        }

        // Valida nota
        if (nota == null || nota < 1 || nota > 5) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A nota deve ser entre 1 e 5.");
        }

        // Valida comentário
        if (comentario != null && comentario.length() > 100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Comentário deve ter no máximo 100 caracteres.");
        }

        Avaliacao av = new Avaliacao();
        av.setTurnoId(turnoId);
        av.setAvaliadorId(avaliadorId);
        av.setAvaliadoId(avaliadoId);
        av.setNota(nota);
        av.setComentario(comentario);
        avaliacaoRepo.save(av);

        // Atualiza média do avaliado
        atualizarMedia(avaliadoId);

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("mensagem", "Avaliação registrada com sucesso!");
        resp.put("nota", nota);
        return resp;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/avaliacoes/usuario/{usuarioId}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Avaliações recebidas por um usuário")
    @GetMapping("/usuario/{usuarioId}")
    public Map<String, Object> avaliacoesDoUsuario(@PathVariable Long usuarioId) {
        List<Avaliacao> lista = avaliacaoRepo.findByAvaliadoIdOrderByCriadoEmDesc(usuarioId);

        double media = lista.stream().mapToInt(Avaliacao::getNota).average().orElse(0.0);
        media = Math.round(media * 10.0) / 10.0;

        Map<String, Long> dist = new LinkedHashMap<>();
        dist.put("5estrelas", lista.stream().filter(a -> a.getNota() == 5).count());
        dist.put("4estrelas", lista.stream().filter(a -> a.getNota() == 4).count());
        dist.put("3estrelas", lista.stream().filter(a -> a.getNota() == 3).count());
        dist.put("2estrelas", lista.stream().filter(a -> a.getNota() == 2).count());
        dist.put("1estrela",  lista.stream().filter(a -> a.getNota() == 1).count());

        DateTimeFormatter fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd");
        List<Map<String, Object>> avaliacoes = lista.stream()
                .limit(20)
                .map(a -> {
                    String nomeAvaliador = usuarioRepo.findById(a.getAvaliadorId())
                            .map(Usuario::getNome).orElse("Usuário");
                    Map<String, Object> m = new LinkedHashMap<>();
                    m.put("turnoId", a.getTurnoId());
                    m.put("nota", a.getNota());
                    m.put("comentario", a.getComentario());
                    m.put("nomeAvaliador", nomeAvaliador);
                    m.put("data", a.getCriadoEm().format(fmt));
                    return m;
                })
                .collect(Collectors.toList());

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("mediaGeral", media);
        resp.put("totalAvaliacoes", lista.size());
        resp.put("distribuicao", dist);
        resp.put("avaliacoes", avaliacoes);
        return resp;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/avaliacoes/feitas/{avaliadorId}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "IDs de turnos que o usuário já avaliou")
    @GetMapping("/feitas/{avaliadorId}")
    public Map<String, Object> turnosAvaliados(@PathVariable Long avaliadorId) {
        List<Long> ids = avaliacaoRepo.findByAvaliadorId(avaliadorId)
                .stream()
                .map(Avaliacao::getTurnoId)
                .distinct()
                .collect(Collectors.toList());
        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("turnoIds", ids);
        return resp;
    }

    // ─────────────────────────────────────────────────────────
    // GET /api/avaliacoes/turno/{turnoId}/pendentes/{usuarioId}
    // ─────────────────────────────────────────────────────────

    @Operation(summary = "Verifica se usuário precisa avaliar o turno")
    @GetMapping("/turno/{turnoId}/pendentes/{usuarioId}")
    public Map<String, Boolean> pendente(@PathVariable Long turnoId,
                                          @PathVariable Long usuarioId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado."));

        boolean participou = usuarioId.equals(turno.getLojistId())
                || usuarioId.equals(turno.getMotoboyId());

        boolean jaAvaliou = avaliacaoRepo.existsByTurnoIdAndAvaliadorId(turnoId, usuarioId);
        boolean precisaAvaliar = participou
                && "finalizado".equals(turno.getStatus())
                && !jaAvaliou;

        return Map.of("precisaAvaliar", precisaAvaliar);
    }

    // ── Helpers ──────────────────────────────────────────────

    private void atualizarMedia(Long usuarioId) {
        List<Avaliacao> todas = avaliacaoRepo.findByAvaliadoIdOrderByCriadoEmDesc(usuarioId);
        double media = Math.round(
                todas.stream().mapToInt(Avaliacao::getNota).average().orElse(0.0) * 10.0) / 10.0;

        usuarioRepo.findById(usuarioId).ifPresent(u -> {
            u.setMediaAvaliacao(media);
            usuarioRepo.save(u);
        });
    }

    private Long toLong(Object o) {
        if (o instanceof Integer i) return i.longValue();
        if (o instanceof Long l) return l;
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "ID inválido.");
    }
}
