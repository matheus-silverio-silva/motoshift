package com.motoshift.repository;

/** Quantas inscrições um turno tem — uma linha por turno, numa consulta só. */
public record ContagemPorTurno(Long turnoId, Long total) {}
