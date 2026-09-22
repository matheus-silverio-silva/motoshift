package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Que tipo de operacao o gateway esta executando numa {@link Cobranca}.
 *
 * As duas pontas por onde o dinheiro entra e sai da plataforma: RECARGA traz
 * dinheiro de fora para o saldo disponivel; SAQUE leva do saldo disponivel para
 * a chave Pix. Tudo o que acontece entre as duas e transferencia interna e nao
 * passa pelo gateway.
 */
public enum TipoCobranca {

    RECARGA("recarga"),
    SAQUE("saque");

    private final String valor;

    TipoCobranca(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static TipoCobranca de(String valor) {
        if (valor == null) return null;
        for (TipoCobranca t : values()) {
            if (t.valor.equals(valor)) return t;
        }
        throw new IllegalArgumentException("Tipo de cobrança desconhecido: " + valor);
    }
}
