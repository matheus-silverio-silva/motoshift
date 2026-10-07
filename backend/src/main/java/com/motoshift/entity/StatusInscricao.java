package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Estados da inscrição de um entregador num turno.
 *
 * Não é o {@link StatusTurno} com outro nome — a inscrição nasce aceita, e daí
 * só termina: paga ({@link #FINALIZADO}), em falta ({@link #FALTOU}) ou
 * cancelada. Ela nunca fica "aberta" (quem está aberto é o turno, enquanto
 * houver vaga) nem "expirada". São enums separados de propósito: um único enum
 * compartilhado deixaria o compilador aceitar
 * {@code inscricao.setStatus(ABERTO)}, que não significa nada.
 *
 * Mesma mecânica de valor minúsculo do {@link StatusTurno}: converter para o
 * banco, {@code @JsonValue} para a API, {@code name()} nunca. O domínio também
 * está no banco, no CHECK {@code ck_inscricao_status} da V21.
 */
public enum StatusInscricao {

    ACEITO("aceito"),
    /** Fez check-in e foi pago na finalização. */
    FINALIZADO("finalizado"),
    /**
     * Aceitou e não fez check-in: o turno foi finalizado sem ele. Não recebe —
     * a parte dele volta ao lojista como sobra — e não perde score (V21).
     */
    FALTOU("faltou"),
    CANCELADO("cancelado");

    private final String valor;

    StatusInscricao(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    /**
     * Está no turno (ACEITO) ou esteve e foi pago (FINALIZADO). Quem cancelou
     * e quem faltou não participam dele: não avaliam, não são avaliados e não
     * têm pagamento a documentar.
     */
    public boolean valeNoTurno() {
        return this == ACEITO || this == FINALIZADO;
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
