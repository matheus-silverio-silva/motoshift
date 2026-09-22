package com.motoshift.service.gateway;

import java.math.BigDecimal;

/**
 * O que o gateway devolve ao abrir uma cobranca Pix.
 *
 * @param codigoCopiaECola a string que o pagador cola no app do banco
 * @param valor            o valor cobrado, repetido pelo gateway
 * @param referencia       identificador do pedido no provedor
 */
public record CobrancaPix(String codigoCopiaECola, BigDecimal valor, String referencia) {
}
