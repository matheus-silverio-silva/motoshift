package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * O que um lançamento do extrato representa.
 *
 * Era String livre, e é justamente o registro de dinheiro: turno e inscrição
 * já tinham virado enum, a transação não. Conviviam duas gerações de valor —
 * "turno" (crédito anterior à liquidação automática) e "pagamento_recebido" —,
 * e o CarteiraService carregava uma lista só para somar as duas. A V10 reescreveu
 * "turno" como "pagamento_recebido" no banco e a lista de compatibilidade saiu.
 *
 * O domínio é o documentado desde a V4 e que o app já sabe desenhar
 * (Motoshift/lib/models/transacao.dart). Quem emite cada um, e o que ele faz
 * com o saldo, está na tabela de {@code service.ledger.Movimento} — a única
 * fonte dessa resposta. {@link #BONUS} é o único que nenhum fluxo emite hoje;
 * existe para que uma linha antiga com esse valor seja lida sem estourar. A
 * lista bate com o CHECK do banco (V10, ampliado na V14) — valor fora dela é
 * erro alto, lá e aqui.
 *
 * Mesmo padrão dos outros enums: o valor gravado é minúsculo e explícito, nunca
 * {@code name()} (ver {@link StatusTurno}).
 */
public enum TipoTransacao {

    RECARGA("recarga"),
    RESERVA("reserva"),
    LIBERACAO_RESERVA("liberacao_reserva"),
    PAGAMENTO_ENVIADO("pagamento_enviado"),
    PAGAMENTO_RECEBIDO("pagamento_recebido"),
    SAQUE("saque"),
    BONUS("bonus"),
    ESTORNO("estorno"),

    /**
     * ISS retido na fonte sobre um pagamento recebido. Só existe com
     * {@code motoshift.fiscal.reter-na-fonte=true} — ver
     * {@code service.fiscal.CalculoTributario}.
     */
    RETENCAO_ISS("retencao_iss"),

    /** IRRF retido na fonte. Mesma condição do {@link #RETENCAO_ISS}. */
    RETENCAO_IRRF("retencao_irrf");

    private final String valor;

    TipoTransacao(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static TipoTransacao de(String valor) {
        if (valor == null) return null;
        for (TipoTransacao t : values()) {
            if (t.valor.equals(valor)) return t;
        }
        throw new IllegalArgumentException("Tipo de transação desconhecido: " + valor);
    }
}
