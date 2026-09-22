package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Direcao do dinheiro num lancamento, do ponto de vista do dono do extrato.
 *
 * <p><b>Por que uma coluna e nao um switch no cliente.</b> O app decidia o sinal
 * de cada linha por uma lista de tipos ("saque, reserva e pagamento_enviado sao
 * saida; o resto e entrada"). Toda vez que o backend passa a emitir um tipo
 * novo, a versao do app que ja esta instalada o desenha com sinal de mais e cor
 * de credito — uma reserva de R$ 360 aparecendo como se fosse dinheiro
 * entrando. O sinal passa a vir gravado junto com o lancamento.
 *
 * <p><b>O que esta coluna NAO e.</b> Ela e o sinal da tela, nao a aritmetica do
 * saldo. {@code reserva} e {@code liberacao_reserva} apenas movem dinheiro
 * entre os dois bolsos da mesma carteira (disponivel e bloqueado) e nao mudam o
 * patrimonio; {@code pagamento_enviado} sai do bloqueado e nao encosta no
 * disponivel. Somar {@code valor} com o sinal daqui NAO devolve o saldo. Quem
 * sabe qual bolso se move e quanto e o {@link com.motoshift.service.ledger.Movimento},
 * em um lugar so — e e de la que saem as invariantes.
 *
 * Mesmo padrao dos outros enums do projeto: valor minusculo e explicito, nunca
 * {@code name()} (ver {@link StatusTurno}).
 */
public enum NaturezaTransacao {

    /** Entrou dinheiro para o dono do extrato: recarga, pagamento recebido, estorno. */
    CREDITO("credito"),

    /** Saiu dinheiro do dono do extrato: saque, reserva, pagamento enviado. */
    DEBITO("debito");

    private final String valor;

    NaturezaTransacao(String valor) {
        this.valor = valor;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    @JsonCreator
    public static NaturezaTransacao de(String valor) {
        if (valor == null) return null;
        for (NaturezaTransacao n : values()) {
            if (n.valor.equals(valor)) return n;
        }
        throw new IllegalArgumentException("Natureza de transação desconhecida: " + valor);
    }
}
