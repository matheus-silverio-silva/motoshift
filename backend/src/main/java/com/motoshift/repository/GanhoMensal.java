package com.motoshift.repository;

import java.math.BigDecimal;

/** Uma barra do grafico da carteira: o total liquidado num mes. */
public record GanhoMensal(Integer ano, Integer mes, BigDecimal total) {}
