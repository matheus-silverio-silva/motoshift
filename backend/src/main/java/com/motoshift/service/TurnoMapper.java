package com.motoshift.service;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.Turno;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.util.GeoUtils;
import org.springframework.stereotype.Component;

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
     * Preenche {@code vagasPreenchidas} com a contagem de inscricoes ativas
     * (status ACEITO), para que toda listagem exponha a ocupacao real.
     */
    public TurnoResponse toResponse(Turno t) {
        return toResponse(t, null, null);
    }

    /**
     * Igual ao anterior, mas preenche {@code distanciaKm} quando a requisicao
     * informou a posicao do usuario (SCRUM-18).
     */
    public TurnoResponse toResponse(Turno t, Double origemLat, Double origemLng) {
        TurnoResponse r = TurnoResponse.from(t);
        long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), StatusInscricao.ACEITO);
        r.setVagasPreenchidas((int) ativas);
        r.setDistanciaKm(GeoUtils.arredondar1(
                GeoUtils.distanciaKm(origemLat, origemLng, t.getLatitude(), t.getLongitude())));
        return r;
    }
}
