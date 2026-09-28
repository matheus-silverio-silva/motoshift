package com.motoshift.dto;

import com.motoshift.entity.Transacao;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Uma gorjeta dada: a quem, quanto e quando. O {@code transacaoId} é o lado
 * do lojista no extrato (o {@code bonus_enviado}) — é dele que sai o
 * comprovante.
 */
public record GorjetaResponse(Long turnoId, Long entregadorId, BigDecimal valor,
                              Long transacaoId, LocalDateTime criadaEm) {

    public static GorjetaResponse de(Long turnoId, Long entregadorId, Transacao debito) {
        return new GorjetaResponse(turnoId, entregadorId, debito.getValor(),
                debito.getId(), debito.getCriadoEm());
    }
}
