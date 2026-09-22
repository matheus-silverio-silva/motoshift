package com.motoshift.repository;

import java.math.BigDecimal;

/**
 * Quanto um turno ainda mantem bloqueado na carteira do lojista.
 *
 * <p>E a reserva menos o que ja saiu dela: pagamentos feitos e liberacoes. A
 * soma de todas as reservas abertas de um usuario tem de dar exatamente o
 * saldoBloqueado dele — sao duas leituras do mesmo fato, e o resumo mostra as
 * duas lado a lado justamente para que uma divergencia apareca.
 */
public record ReservaAberta(Long turnoId, String titulo, BigDecimal valor) {
}
