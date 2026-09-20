package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Situacao de uma {@link Cobranca} no gateway.
 *
 * <p><b>Uma palavra por conceito.</b> A recarga nasce "pendente" (o Pix foi
 * gerado e ninguem pagou) e o saque nasce "solicitado" (o pedido foi aceito e o
 * dinheiro ainda nao chegou na chave). Sao o mesmo estado — operacao aberta no
 * gateway — e ficam com o mesmo nome, {@link #PENDENTE}, em vez de duas
 * palavras para a mesma coisa. O projeto ja pagou esse preco uma vez, com
 * "processado" e "concluido" convivendo em {@link StatusTransacao} ate a V10.
 *
 * <p><b>FALHOU nao e o fim do dinheiro.</b> Um saque que falha no gateway tem o
 * valor devolvido ao disponivel por um lancamento de estorno; o debito original
 * continua no extrato, porque ele realmente aconteceu. Ver
 * {@code docs/financeiro/FLUXO-FINANCEIRO.md}.
 */
public enum StatusCobranca {

    /** Aberta no gateway: recarga aguardando pagamento, saque aguardando envio. */
    PENDENTE("pendente"),

    /** O gateway confirmou: a recarga foi paga ou o saque caiu na chave Pix. */
    CONCLUIDO("concluido"),

    /** O gateway recusou. Em saque, dispara o estorno automatico. */
    FALHOU("falhou");

    private final String valor;

    StatusCobranca(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static StatusCobranca de(String valor) {
        if (valor == null) return null;
        for (StatusCobranca s : values()) {
            if (s.valor.equals(valor)) return s;
        }
        throw new IllegalArgumentException("Status de cobrança desconhecido: " + valor);
    }

    /** Operacao ja encerrada no gateway: nao muda mais de estado. */
    public boolean isEncerrada() {
        return this == CONCLUIDO || this == FALHOU;
    }
}
