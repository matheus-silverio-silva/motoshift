package com.motoshift.repository;

import java.time.LocalDateTime;

/**
 * Uma vaga de que o entregador desistiu: o turno, e quando ele saiu.
 *
 * <p>Projeção de {@link TurnoInscricaoRepository#desistenciasDe}. Desistir não
 * cancela o turno — a vaga reabre e ele segue —, então a desistência não
 * aparece em {@code turnos}: quem a guarda é a inscrição (V22).
 *
 * @param turnoId       o turno de que ele saiu
 * @param titulo        o título, para a lista de eventos do score
 * @param inicioDoTurno a hora marcada — contra ela se mede "em cima da hora"
 * @param canceladoEm   quando desistiu
 */
public record Desistencia(Long turnoId, String titulo, LocalDateTime inicioDoTurno,
                          LocalDateTime canceladoEm) {}
