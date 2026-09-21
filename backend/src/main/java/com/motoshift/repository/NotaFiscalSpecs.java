package com.motoshift.repository;

import com.motoshift.dto.NotaFiscalFiltro;
import com.motoshift.entity.NotaFiscal;
import jakarta.persistence.criteria.Predicate;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;

/**
 * O filtro da lista de notas, traduzido para o banco.
 *
 * <p>A condição de partida é sempre "notas em que o usuário é parte" — o
 * filtro só estreita, nunca alarga. Parâmetro inválido é 400 aqui, e não uma
 * lista vazia: {@code papel=prestdor} devolvendo nada pareceria "você não tem
 * notas", que é outra informação.
 */
public final class NotaFiscalSpecs {

    private NotaFiscalSpecs() {}

    public static Specification<NotaFiscal> de(Long usuarioId, NotaFiscalFiltro f) {
        validar(f);
        return (raiz, consulta, cb) -> {
            List<Predicate> e = new ArrayList<>();
            String papel = f.getPapel() == null ? null : f.getPapel().trim().toLowerCase();

            if ("prestador".equals(papel)) {
                e.add(cb.equal(raiz.get("prestadorId"), usuarioId));
            } else if ("tomador".equals(papel)) {
                e.add(cb.equal(raiz.get("tomadorId"), usuarioId));
            } else {
                e.add(cb.or(cb.equal(raiz.get("prestadorId"), usuarioId),
                        cb.equal(raiz.get("tomadorId"), usuarioId)));
            }

            if (f.getContraparteId() != null) {
                // O outro lado da nota, qualquer que seja o meu.
                e.add(cb.or(
                        cb.and(cb.equal(raiz.get("prestadorId"), usuarioId),
                                cb.equal(raiz.get("tomadorId"), f.getContraparteId())),
                        cb.and(cb.equal(raiz.get("tomadorId"), usuarioId),
                                cb.equal(raiz.get("prestadorId"), f.getContraparteId()))));
            }
            if (f.getCompetenciaDe() != null) {
                e.add(cb.greaterThanOrEqualTo(raiz.get("competencia"), f.getCompetenciaDe()));
            }
            if (f.getCompetenciaAte() != null) {
                e.add(cb.lessThan(raiz.get("competencia"), f.getCompetenciaAte()));
            }
            String status = f.getStatus() == null ? null : f.getStatus().trim().toLowerCase();
            if ("emitida".equals(status)) {
                e.add(cb.isNull(raiz.get("canceladaEm")));
            } else if ("cancelada".equals(status)) {
                e.add(cb.isNotNull(raiz.get("canceladaEm")));
            }
            if (f.getTurnoId() != null) {
                e.add(cb.equal(raiz.get("turnoId"), f.getTurnoId()));
            }
            return cb.and(e.toArray(Predicate[]::new));
        };
    }

    private static void validar(NotaFiscalFiltro f) {
        String papel = f.getPapel();
        if (papel != null && !papel.isBlank()
                && !List.of("prestador", "tomador").contains(papel.trim().toLowerCase())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "papel deve ser 'prestador' ou 'tomador'.");
        }
        String status = f.getStatus();
        if (status != null && !status.isBlank()
                && !List.of("emitida", "cancelada").contains(status.trim().toLowerCase())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "status deve ser 'emitida' ou 'cancelada'.");
        }
        if (f.getCompetenciaDeBruta() != null && f.getCompetenciaAteBruta() != null
                && f.getCompetenciaAteBruta().isBefore(f.getCompetenciaDeBruta())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "competenciaAte anterior a competenciaDe.");
        }
    }
}
