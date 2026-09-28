package com.motoshift.dto;

import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

/** A gorjeta que o lojista quer dar a um entregador do turno. */
public record GorjetaRequest(@NotNull Long entregadorId, @NotNull BigDecimal valor) {}
