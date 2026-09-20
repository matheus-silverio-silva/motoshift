package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Situação de um lançamento do extrato.
 *
 * {@link #PENDENTE} é dívida reconhecida e ainda não paga — o turno foi
 * finalizado e o pagamento não liquidou. {@link #CONCLUIDO} é dinheiro que já é
 * do usuário, e é o único status que entra em "ganhos do mês".
 *
 * Havia duas palavras para concluído: "processado" (legado) e "concluido". A
 * V10 unificou no banco e o CarteiraService deixou de somar as duas.
 *
 * Não confundir com {@link StatusPagamento}, que é do turno e da inscrição.
 */
public enum StatusTransacao {

    PENDENTE("pendente"),
    CONCLUIDO("concluido"),
    FALHOU("falhou"),
    ESTORNADO("estornado");

    private final String valor;

    StatusTransacao(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static StatusTransacao de(String valor) {
        if (valor == null) return null;
        for (StatusTransacao s : values()) {
            if (s.valor.equals(valor)) return s;
        }
        throw new IllegalArgumentException("Status de transação desconhecido: " + valor);
    }
}
