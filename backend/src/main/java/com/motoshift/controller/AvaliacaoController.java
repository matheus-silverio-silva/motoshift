package com.motoshift.controller;

import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
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
    private final TurnoInscricaoRepository inscricaoRepo;

    public AvaliacaoController(AvaliacaoRepository avaliacaoRepo,
                                TurnoRepository turnoRepo,
                                UsuarioRepository usuarioRepo,
                                TurnoInscricaoRepository inscricaoRepo) {
        this.avaliacaoRepo = avaliacaoRepo;
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.inscricaoRepo = inscricaoRepo;
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

        // Valida participação do AVALIADOR.
        // Antes só olhava turno.motoboyId; entregador que entrou por vaga extra
        // tomava 403 e nunca conseguia avaliar.
        if (!participou(turno, avaliadorId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Avaliador não participou deste turno.");
        }
        // O alvo também precisa ter participado, e ninguém avalia a si mesmo.
        if (avaliadoId == null || avaliadorId.equals(avaliadoId) || !participou(turno, avaliadoId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Avaliado inválido para este turno.");
        }

        // Duplicata é o TRIO. Com (turno, avaliador) o lojista de um turno
        // multi-vaga era barrado depois de avaliar o primeiro entregador.
        if (avaliacaoRepo.existsByTurnoIdAndAvaliadorIdAndAvaliadoId(turnoId, avaliadorId, avaliadoId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Você já avaliou este participante neste turno.");
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

    @Operation(summary = "Quem o usuário ainda precisa avaliar neste turno",
            description = "Em turno multi-vaga o lojista avalia cada entregador. "
                    + "Mantém 'precisaAvaliar' por compatibilidade e acrescenta a lista 'pendentes'.")
    @GetMapping("/turno/{turnoId}/pendentes/{usuarioId}")
    public Map<String, Object> pendente(@PathVariable Long turnoId,
                                        @PathVariable Long usuarioId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado."));

        List<Map<String, Object>> pendentes = new ArrayList<>();
        if (participou(turno, usuarioId) && "finalizado".equals(turno.getStatus())) {
            for (Long alvo : alvosDeAvaliacao(turno, usuarioId)) {
                if (avaliacaoRepo.existsByTurnoIdAndAvaliadorIdAndAvaliadoId(turnoId, usuarioId, alvo)) {
                    continue;
                }
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("usuarioId", alvo);
                m.put("nome", usuarioRepo.findById(alvo).map(Usuario::getNome).orElse("Usuário"));
                pendentes.add(m);
            }
        }

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("precisaAvaliar", !pendentes.isEmpty());
        resp.put("pendentes", pendentes);
        return resp;
    }

    /** Participou do turno como lojista, motoboy principal ou inscrito. */
    private boolean participou(Turno turno, Long usuarioId) {
        if (usuarioId == null) return false;
        if (usuarioId.equals(turno.getLojistId())) return true;
        if (usuarioId.equals(turno.getMotoboyId())) return true;
        return inscricaoRepo.findByTurnoIdAndMotoboyId(turno.getId(), usuarioId)
                .filter(i -> !"cancelado".equals(i.getStatus()))
                .isPresent();
    }

    /** Lojista avalia todos os entregadores; entregador avalia o lojista. */
    private List<Long> alvosDeAvaliacao(Turno turno, Long usuarioId) {
        if (!usuarioId.equals(turno.getLojistId())) {
            return turno.getLojistId() == null ? List.of() : List.of(turno.getLojistId());
        }
        List<Long> ids = inscricaoRepo.findByTurnoId(turno.getId()).stream()
                .filter(i -> !"cancelado".equals(i.getStatus()))
                .map(TurnoInscricao::getMotoboyId)
                .distinct()
                .collect(Collectors.toList());
        // Legado: turno aceito antes do sistema de vagas não tem inscrição.
        if (ids.isEmpty() && turno.getMotoboyId() != null) {
            ids = List.of(turno.getMotoboyId());
        }
        return ids;
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
