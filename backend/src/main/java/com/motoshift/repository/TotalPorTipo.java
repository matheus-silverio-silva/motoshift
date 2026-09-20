package com.motoshift.repository;

import com.motoshift.entity.TipoTransacao;

import java.math.BigDecimal;

/** Quanto cada tipo de lancamento somou no periodo — a quebra do resumo. */
public record TotalPorTipo(TipoTransacao tipo, BigDecimal total, long quantidade) {
}
