package com.motoshift.service;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.Turno;
import com.motoshift.repository.ContagemPorTurno;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.util.GeoUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Turno (entidade) para TurnoResponse (o que o app recebe).
 *
 * Saiu de dentro do TurnoService quando ele foi dividido: os tres servicos de
 * turno devolvem TurnoResponse, e sem um lugar comum a montagem seria copiada
 * tres vezes — incluindo a contagem de vagas, que e o campo mais facil de
 * esquecer de preencher.
 */
@Component
public class TurnoMapper {

    private final TurnoInscricaoRepository inscricaoRepo;

    public TurnoMapper(TurnoInscricaoRepository inscricaoRepo) {
        this.inscricaoRepo = inscricaoRepo;
    }

    /**
     * Um turno. Preenche {@code vagasPreenchidas} com a contagem de inscricoes
     * ativas (status ACEITO), para que a resposta exponha a ocupacao real, e
     * {@code algumCheckin} — o que o app usa para saber se finalizar valeria.
     */
    public TurnoResponse toResponse(Turno t) {
        return toResponse(t, null, null);
    }

    /**
     * Igual ao anterior, mas preenche {@code distanciaKm} quando a requisicao
     * informou a posicao do usuario (SCRUM-18).
     */
    public TurnoResponse toResponse(Turno t, Double origemLat, Double origemLng) {
        long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), StatusInscricao.ACEITO);
        boolean checkin = inscricaoRepo.existsByTurnoIdAndCheckinEmIsNotNull(t.getId());
        return montar(t, ativas, checkin, origemLat, origemLng);
    }

    /**
     * Uma lista de turnos com UMA contagem de vagas para todos.
     *
     * Montar a lista chamando {@link #toResponse(Turno)} em cada item fazia um
     * COUNT por turno: a listagem de N turnos disparava N+1 consultas.
     */
    public List<TurnoResponse> toResponses(List<Turno> turnos, Double origemLat, Double origemLng) {
        Map<Long, Long> ativas = contarAtivas(turnos);
        Set<Long> comCheckin = comCheckin(turnos);
        return turnos.stream()
                .map(t -> montar(t, ativas.getOrDefault(t.getId(), 0L),
                        comCheckin.contains(t.getId()), origemLat, origemLng))
                .toList();
    }

    public List<TurnoResponse> toResponses(List<Turno> turnos) {
        return toResponses(turnos, null, null);
    }

    /** A pagina montada em lote, preservando total e posicao. */
    public Page<TurnoResponse> toResponses(Page<Turno> pagina) {
        return new PageImpl<>(toResponses(pagina.getContent()),
                pagina.getPageable(), pagina.getTotalElements());
    }

    private Map<Long, Long> contarAtivas(List<Turno> turnos) {
        List<Long> ids = turnos.stream().map(Turno::getId).filter(Objects::nonNull).toList();
        Map<Long, Long> porTurno = new HashMap<>();
        if (ids.isEmpty()) return porTurno;
        for (ContagemPorTurno c : inscricaoRepo.contarPorTurno(ids, StatusInscricao.ACEITO)) {
            porTurno.put(c.turnoId(), c.total());
        }
        return porTurno;
    }

    /** Os turnos da lista em que alguem ja fez check-in, numa consulta so. */
    private Set<Long> comCheckin(List<Turno> turnos) {
        List<Long> ids = turnos.stream().map(Turno::getId).filter(Objects::nonNull).toList();
        if (ids.isEmpty()) return Set.of();
        return new HashSet<>(inscricaoRepo.turnosComCheckin(ids));
    }

    private static TurnoResponse montar(Turno t, long ativas, boolean algumCheckin,
                                        Double origemLat, Double origemLng) {
        TurnoResponse r = TurnoResponse.from(t);
        r.setVagasPreenchidas((int) ativas);
        r.setAlgumCheckin(algumCheckin);
        r.setDistanciaKm(GeoUtils.arredondar1(
                GeoUtils.distanciaKm(origemLat, origemLng, t.getLatitude(), t.getLongitude())));
        return r;
    }
}
