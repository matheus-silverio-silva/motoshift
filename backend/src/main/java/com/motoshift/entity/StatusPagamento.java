package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Estado do pagamento, tanto do turno quanto de cada inscrição.
 *
 * Um enum só para os dois campos porque a regra é a mesma: PENDENTE quando a
 * dívida existe, PAGO quando as duas partes confirmaram.
 *
 * <p><b>null é um terceiro estado com significado.</b> A coluna é anulável e
 * "sem valor" quer dizer "o turno ainda não foi finalizado, então não há o que
 * pagar" — diferente de PENDENTE, que é "finalizado e devendo". Por isso não há
 * uma constante NAO_APLICAVEL: inventá-la exigiria um UPDATE em todas as linhas
 * de turnos ainda não finalizados só para trocar null por um nome.
 *
 * Não confundir com {@link StatusTransacao}, que é o status do lançamento no
 * extrato — outro campo, de outra entidade.
 */
public enum StatusPagamento {

    PENDENTE("pendente"),
    PAGO("pago");

    private final String valor;

    StatusPagamento(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static StatusPagamento de(String valor) {
        if (valor == null) return null;
        for (StatusPagamento s : values()) {
            if (s.valor.equals(valor)) return s;
        }
        throw new IllegalArgumentException("Status de pagamento desconhecido: " + valor);
    }
}
