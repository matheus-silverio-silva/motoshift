package com.motoshift.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Um ponto da serie de fluxo de caixa.
 *
 * @param inicio  primeiro dia do balde (o proprio dia, a segunda-feira da
 *                semana ou o dia 1 do mes)
 * @param rotulo  como a tela escreve o periodo: "05/09", "01-07/09", "09/2026"
 * @param entradas soma dos creditos do periodo
 * @param saidas   soma dos debitos do periodo, sempre positiva
 * @param liquido  entradas menos saidas — pode ser negativo, e deve mesmo
 */
public record FluxoPontoResponse(LocalDate inicio, String rotulo,
                                 BigDecimal entradas, BigDecimal saidas,
                                 BigDecimal liquido) {
}
