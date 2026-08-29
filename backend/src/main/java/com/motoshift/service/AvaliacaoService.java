package com.motoshift.service;

import com.motoshift.dto.AvaliacaoRequest;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Avaliacao mutua entre lojista e entregador.
 *
 * As regras vieram do controller: quem pode avaliar quem, o que conta como
 * duplicata em turno multi-vaga, e o recalculo da media do avaliado. As duas
 * primeiras ja tinham historico de bug (o entregador de vaga extra tomava 403;
 * o lojista era barrado depois de avaliar o primeiro entregador) — sao regras
 * que precisam de um lugar proprio para poderem ser testadas isoladamente.
 */
@Service
public class AvaliacaoService {

    private static final DateTimeFormatter DATA_ISO = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    private final AvaliacaoRepository avaliacaoRepo;
    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TurnoInscricaoRepository inscricaoRepo;

    public AvaliacaoService(AvaliacaoRepository avaliacaoRepo,
                            TurnoRepository turnoRepo,
                            UsuarioRepository usuarioRepo,
                            TurnoInscricaoRepository inscricaoRepo) {
        this.avaliacaoRepo = avaliacaoRepo;
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.inscricaoRepo = inscricaoRepo;
    }

    @Transactional
    public Map<String, Object> avaliar(AvaliacaoRequest req, Long avaliadorId) {
        Long turnoId = req.getTurnoId();
        Long avaliadoId = req.getAvaliadoId();

        Turno turno = carregarTurno(turnoId);
        if (turno.getStatus() != StatusTurno.FINALIZADO) {
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
        if (avaliadorId.equals(avaliadoId) || !participou(turno, avaliadoId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Avaliado inválido para este turno.");
        }

        // Duplicata é o TRIO. Com (turno, avaliador) o lojista de um turno
        // multi-vaga era barrado depois de avaliar o primeiro entregador.
        if (avaliacaoRepo.existsByTurnoIdAndAvaliadorIdAndAvaliadoId(turnoId, avaliadorId, avaliadoId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Você já avaliou este participante neste turno.");
        }

        Avaliacao av = new Avaliacao();
        av.setTurnoId(turnoId);
        av.setAvaliadorId(avaliadorId);
        av.setAvaliadoId(avaliadoId);
        av.setNota(req.getNota());
        av.setComentario(req.getComentario());
        avaliacaoRepo.save(av);

        atualizarMedia(avaliadoId);

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("mensagem", "Avaliação registrada com sucesso!");
        resp.put("nota", req.getNota());
        return resp;
    }

    /** Avaliacoes recebidas por um usuario, com media e distribuicao por estrela. */
    public Map<String, Object> recebidasPor(Long usuarioId) {
        List<Avaliacao> lista = avaliacaoRepo.findByAvaliadoIdOrderByCriadoEmDesc(usuarioId);

        double media = lista.stream().mapToInt(Avaliacao::getNota).average().orElse(0.0);
        media = Math.round(media * 10.0) / 10.0;

        Map<String, Long> dist = new LinkedHashMap<>();
        dist.put("5estrelas", contarNota(lista, 5));
        dist.put("4estrelas", contarNota(lista, 4));
        dist.put("3estrelas", contarNota(lista, 3));
        dist.put("2estrelas", contarNota(lista, 2));
        dist.put("1estrela",  contarNota(lista, 1));

        List<Map<String, Object>> avaliacoes = lista.stream()
                .limit(20)
                .map(a -> {
                    Map<String, Object> m = new LinkedHashMap<>();
                    m.put("turnoId", a.getTurnoId());
                    m.put("nota", a.getNota());
                    m.put("comentario", a.getComentario());
                    m.put("nomeAvaliador", usuarioRepo.findById(a.getAvaliadorId())
                            .map(Usuario::getNome).orElse("Usuário"));
                    m.put("data", a.getCriadoEm().format(DATA_ISO));
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

    /** Ids dos turnos em que o usuario ja avaliou alguem. */
    public Map<String, Object> turnosAvaliadosPor(Long avaliadorId) {
        List<Long> ids = avaliacaoRepo.findByAvaliadorId(avaliadorId).stream()
                .map(Avaliacao::getTurnoId)
                .distinct()
                .collect(Collectors.toList());

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("turnoIds", ids);
        return resp;
    }

    /**
     * Quem o usuario ainda precisa avaliar naquele turno. Mantem
     * {@code precisaAvaliar} por compatibilidade com as telas antigas e
     * acrescenta a lista, necessaria no turno multi-vaga.
     */
    public Map<String, Object> pendentesNoTurno(Long turnoId, Long usuarioId) {
        Turno turno = carregarTurno(turnoId);

        List<Map<String, Object>> pendentes = new ArrayList<>();
        if (participou(turno, usuarioId) && turno.getStatus() == StatusTurno.FINALIZADO) {
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

    // ── Regras internas ──────────────────────────────────────

    private Turno carregarTurno(Long turnoId) {
        return turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Turno não encontrado."));
    }

    private long contarNota(List<Avaliacao> lista, int nota) {
        return lista.stream().filter(a -> a.getNota() == nota).count();
    }

    /** Participou do turno como lojista, motoboy principal ou inscrito. */
    private boolean participou(Turno turno, Long usuarioId) {
        if (usuarioId == null) return false;
        if (usuarioId.equals(turno.getLojistId())) return true;
        if (usuarioId.equals(turno.getMotoboyId())) return true;
        return inscricaoRepo.findByTurnoIdAndMotoboyId(turno.getId(), usuarioId)
                .filter(i -> i.getStatus() != StatusInscricao.CANCELADO)
                .isPresent();
    }

    /** Lojista avalia todos os entregadores; entregador avalia o lojista. */
    private List<Long> alvosDeAvaliacao(Turno turno, Long usuarioId) {
        if (!usuarioId.equals(turno.getLojistId())) {
            return turno.getLojistId() == null ? List.of() : List.of(turno.getLojistId());
        }
        List<Long> ids = inscricaoRepo.findByTurnoId(turno.getId()).stream()
                .filter(i -> i.getStatus() != StatusInscricao.CANCELADO)
                .map(TurnoInscricao::getMotoboyId)
                .distinct()
                .collect(Collectors.toList());
        // Legado: turno aceito antes do sistema de vagas não tem inscrição.
        if (ids.isEmpty() && turno.getMotoboyId() != null) {
            ids = List.of(turno.getMotoboyId());
        }
        return ids;
    }

    private void atualizarMedia(Long usuarioId) {
        List<Avaliacao> todas = avaliacaoRepo.findByAvaliadoIdOrderByCriadoEmDesc(usuarioId);
        double media = Math.round(
                todas.stream().mapToInt(Avaliacao::getNota).average().orElse(0.0) * 10.0) / 10.0;

        usuarioRepo.findById(usuarioId).ifPresent(u -> {
            u.setMediaAvaliacao(media);
            usuarioRepo.save(u);
        });
    }
}
