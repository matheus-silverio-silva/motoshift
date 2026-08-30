package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Estados da inscrição de um entregador num turno.
 *
 * É um subconjunto de {@link StatusTurno} — a inscrição nasce aceita, e daí só
 * termina ou é cancelada; ela nunca fica "aberta" (quem está aberto é o turno,
 * enquanto houver vaga) nem "expirada". São enums separados de propósito: um
 * único enum compartilhado deixaria o compilador aceitar
 * {@code inscricao.setStatus(ABERTO)}, que não significa nada.
 *
 * Mesma mecânica de valor minúsculo do {@link StatusTurno}: converter para o
 * banco, {@code @JsonValue} para a API, {@code name()} nunca.
 */
public enum StatusInscricao {

    ACEITO("aceito"),
    FINALIZADO("finalizado"),
    CANCELADO("cancelado");

    private final String valor;

    StatusInscricao(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static StatusInscricao de(String valor) {
        if (valor == null) return null;
        for (StatusInscricao s : values()) {
            if (s.valor.equals(valor)) return s;
        }
        throw new IllegalArgumentException("Status de inscrição desconhecido: " + valor);
    }
}
