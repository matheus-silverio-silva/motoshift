package com.motoshift.dto;

import java.math.BigDecimal;
import java.util.List;

/**
 * Informe anual SIMULADO — de rendimentos, para o entregador; de serviços
 * tomados, para o lojista.
 *
 * <p>Os números saem do extrato (regime de caixa: o ano é o da data do
 * crédito ou do débito), e não das notas emitidas. Um informe de rendimentos
 * responde "quanto você recebeu", e isso não depende de a nota ter sido
 * gerada: por isso {@link #notasEmitidas} vem ao lado, para mostrar o que ainda
 * falta documentar, em vez de ser a base da conta.
 *
 * @param papel "prestador" (entregador) ou "tomador" (lojista)
 */
public record InformeAnualResponse(
        int ano,
        String papel,
        String titulo,
        BigDecimal total,
        BigDecimal issRetido,
        BigDecimal irrfRetido,
        int pagamentos,
        int notasEmitidas,
        List<PorContraparte> contrapartes,
        List<PorMes> meses,
        boolean simulado,
        String marca) {

    /** O total com uma fonte pagadora (entregador) ou com um prestador (lojista). */
    public record PorContraparte(
            Long contraparteId,
            String nome,
            String documentoTipo,
            String documento,
            BigDecimal total,
            BigDecimal issRetido,
            BigDecimal irrfRetido,
            int pagamentos,
            int notasEmitidas) {}

    /** Mês 1 a 12. Os doze sempre vêm, com zero onde não houve nada. */
    public record PorMes(int mes, BigDecimal total, int pagamentos) {}
}
