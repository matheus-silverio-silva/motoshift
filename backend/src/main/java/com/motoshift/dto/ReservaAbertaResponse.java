package com.motoshift.dto;

import java.math.BigDecimal;

/** Quanto um turno especifico ainda segura na carteira do lojista. */
public record ReservaAbertaResponse(Long turnoId, String titulo, BigDecimal valor) {
}
