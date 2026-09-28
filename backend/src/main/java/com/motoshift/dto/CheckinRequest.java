package com.motoshift.dto;

/**
 * Onde o entregador está ao tocar "Cheguei". Os dois nulos só valem com a
 * trava de proximidade desligada ({@code motoshift.checkin.exigir-proximidade=false}).
 */
public record CheckinRequest(Double latitude, Double longitude) {}
