package com.motoshift.repository;

import java.time.LocalDateTime;

/** Um check-in e a hora marcada do turno — o par que a pontualidade compara. */
public record Chegada(LocalDateTime checkinEm, LocalDateTime inicioDoTurno) {}
