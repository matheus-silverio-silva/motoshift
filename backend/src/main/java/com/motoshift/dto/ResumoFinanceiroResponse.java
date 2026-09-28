package com.motoshift.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * O retrato financeiro de um usuário num período — um para cada papel.
 *
 * <p>Até aqui os dois perfis recebiam os mesmos campos, com o do outro papel
 * zerado: o entregador via "comprometido R$ 0,00", o lojista via "a receber
 * R$ 0,00", e os dois viam "entradas" e "saídas" que diziam coisas diferentes
 * para cada um (a entrada do lojista é recarga, não receita; a saída do
 * entregador é saque, não custo). Agora cada papel recebe só as perguntas que
 * fazem sentido para ele, e o campo do outro papel NÃO VEM no JSON — um zero
 * com o rótulo do outro lado não é informação, é ruído.
 *
 * <p><b>Entregador</b> ({@code papel = "prestador"}): {@code recebido},
 * {@code retencoes} (só com retenção na fonte ligada, ou havendo retenção no
 * período), {@code sacado}, {@code disponivel} e {@code aReceber}.
 *
 * <p><b>Lojista</b> ({@code papel = "tomador"}): {@code recarregado},
 * {@code pagoAEntregadores}, {@code devolvido}, {@code disponivel},
 * {@code bloqueado}, {@code comprometido} e {@code reservasAbertas}.
 *
 * @param papel             "prestador" (entregador) ou "tomador" (lojista)
 * @param dataInicio        começo do período consultado
 * @param dataFim           fim do período consultado, inclusive
 * @param disponivel        saldo que pode ser gasto ou sacado agora
 * @param recebido          entregador: pagamentos de turno recebidos no período
 * @param retencoes         entregador: ISS e IRRF retidos na fonte no período
 * @param sacado            entregador: saques do período menos os estornos de
 *                          saques que o banco recusou — o que de fato saiu
 * @param aReceber          entregador: turnos aceitos que ainda não foram
 *                          finalizados. Não é saldo — é expectativa: o dinheiro
 *                          está bloqueado na carteira do lojista
 * @param recarregado       lojista: recargas do período
 * @param pagoAEntregadores lojista: pagamentos de turno enviados no período
 * @param devolvido         lojista: o que voltou ao disponível no período —
 *                          liberação de reserva (vaga vazia, cancelamento,
 *                          expiração) e estorno
 * @param bloqueado         lojista: saldo preso em turnos publicados
 * @param comprometido      lojista: total das reservas abertas. É o mesmo número
 *                          de {@code bloqueado}, mostrado ao lado da lista que o
 *                          explica — se os dois discordarem, há algo errado e
 *                          aparece na tela
 * @param reservasAbertas   lojista: quanto cada turno ainda segura
 * @param porTipo           quebra do período por tipo de lançamento — só os
 *                          tipos que o usuário tem
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ResumoFinanceiroResponse(
        String papel,
        LocalDate dataInicio,
        LocalDate dataFim,
        BigDecimal disponivel,
        BigDecimal recebido,
        BigDecimal retencoes,
        BigDecimal sacado,
        BigDecimal aReceber,
        BigDecimal recarregado,
        BigDecimal pagoAEntregadores,
        BigDecimal devolvido,
        BigDecimal bloqueado,
        BigDecimal comprometido,
        List<ReservaAbertaResponse> reservasAbertas,
        List<TotalPorTipoResponse> porTipo) {

    public static final String PRESTADOR = "prestador";
    public static final String TOMADOR = "tomador";

    /** O resumo do entregador: nada de recarga, reserva ou comprometido. */
    public static ResumoFinanceiroResponse doEntregador(
            LocalDate de, LocalDate ate, BigDecimal disponivel, BigDecimal recebido,
            BigDecimal retencoes, BigDecimal sacado, BigDecimal aReceber,
            List<TotalPorTipoResponse> porTipo) {
        return new ResumoFinanceiroResponse(PRESTADOR, de, ate, disponivel,
                recebido, retencoes, sacado, aReceber,
                null, null, null, null, null, null, porTipo);
    }

    /** O resumo do lojista: nada de pagamento recebido, saque ou a receber. */
    public static ResumoFinanceiroResponse doLojista(
            LocalDate de, LocalDate ate, BigDecimal disponivel, BigDecimal recarregado,
            BigDecimal pagoAEntregadores, BigDecimal devolvido, BigDecimal bloqueado,
            List<ReservaAbertaResponse> reservasAbertas, List<TotalPorTipoResponse> porTipo) {
        return new ResumoFinanceiroResponse(TOMADOR, de, ate, disponivel,
                null, null, null, null,
                recarregado, pagoAEntregadores, devolvido, bloqueado, bloqueado,
                reservasAbertas, porTipo);
    }
}
