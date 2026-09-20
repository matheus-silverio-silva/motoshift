package com.motoshift.repository;

import com.motoshift.entity.NaturezaTransacao;

import java.math.BigDecimal;

/**
 * Um dia de extrato, somado no banco e separado por entrada e saida.
 *
 * <p>A serie do grafico — por dia, por semana ou por mes — e montada a partir
 * destes baldes. O agrupamento que precisava sair da memoria e o que varre
 * TRANSACOES, e ele acontece aqui, no SQL: o que volta e no maximo um registro
 * por dia e natureza, independentemente de haver cem ou cem mil lancamentos.
 * Dobrar dias em semanas depois disso e trabalho limitado pelo tamanho do
 * periodo, nao pelo volume de dados.
 */
public record PontoDeFluxo(int ano, int mes, int dia,
                           NaturezaTransacao natureza, BigDecimal total) {
}
