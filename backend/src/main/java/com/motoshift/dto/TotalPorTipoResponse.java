package com.motoshift.dto;

import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.TipoTransacao;

import java.math.BigDecimal;

/**
 * Uma linha da quebra por tipo.
 *
 * A natureza vem junto para a tela pintar a linha sem reimplementar a regra —
 * mesmo motivo de a coluna existir no lancamento.
 */
public record TotalPorTipoResponse(TipoTransacao tipo, NaturezaTransacao natureza,
                                   BigDecimal total, long quantidade) {
}
