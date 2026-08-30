package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;

/**
 * Quem esta dentro de um turno — e o 404/403 que decorre disso.
 *
 * Fica em um componente proprio porque tres servicos precisam da mesma
 * resposta: o de ciclo de vida (finalizar, cancelar), o de pagamento e o de
 * consulta. Regra de acesso duplicada e regra de acesso que diverge, e aqui
 * divergir significa deixar entrar quem nao devia.
 */
@Component
public class TurnoAcesso {

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;

    public TurnoAcesso(TurnoRepository turnoRepo, TurnoInscricaoRepository inscricaoRepo) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
    }

    public Turno carregar(Long turnoId) {
        return turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Turno não encontrado"));
    }

    /** Lojista + todos os entregadores nao cancelados do turno. */
    public List<Long> participantes(Turno turno) {
        LinkedHashSet<Long> ids = new LinkedHashSet<>();
        if (turno.getLojistId() != null) ids.add(turno.getLojistId());
        if (turno.getMotoboyId() != null) ids.add(turno.getMotoboyId());
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoId(turno.getId())) {
            if (ins.getStatus() != StatusInscricao.CANCELADO) ids.add(ins.getMotoboyId());
        }
        return new ArrayList<>(ids);
    }

    /**
     * So quem esta no turno mexe nele: o lojista dono ou um entregador inscrito.
     *
     * Finalizar e cancelar nao recebiam usuario nenhum — um PUT com o id do
     * turno bastava para encerrar turno alheio e disparar o credito na carteira.
     */
    public void exigirParticipante(Turno turno, Long usuarioId) {
        if (usuarioId == null || !participantes(turno).contains(usuarioId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: você não participa deste turno.");
        }
    }
}
