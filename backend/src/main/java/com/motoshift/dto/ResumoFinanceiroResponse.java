package com.motoshift.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * O retrato financeiro de um usuário num período.
 *
 * <p>Serve aos dois perfis com os mesmos campos, porque a pergunta é a mesma —
 * <i>quanto entrou, quanto saiu, quanto tenho e quanto está comprometido</i> —
 * e só a resposta muda de sinal. O que é específico de cada papel tem nome
 * próprio: {@code aReceber} é do entregador, {@code comprometido} é do lojista,
 * e cada um vem zerado para quem não tem aquele tipo de pendência.
 *
 * @param dataInicio     começo do período consultado
 * @param dataFim        fim do período consultado, inclusive
 * @param entradas       créditos do período
 * @param saidas         débitos do período, sempre positivos
 * @param liquido        entradas menos saídas
 * @param disponivel     saldo que pode ser gasto ou sacado agora
 * @param bloqueado      saldo preso em turnos publicados e não encerrados
 * @param aReceber       entregador: turnos aceitos que ainda não foram
 *                       finalizados. Não é saldo — é expectativa, e por isso
 *                       fica fora de disponível e de bloqueado
 * @param comprometido   lojista: total das reservas abertas. É o mesmo número
 *                       de {@code bloqueado}, mostrado ao lado da lista que o
 *                       explica — se os dois discordarem, há algo errado e
 *                       aparece na tela
 * @param reservasAbertas quanto cada turno ainda segura
 * @param porTipo        quebra do período por tipo de lançamento
 */
public record ResumoFinanceiroResponse(
        LocalDate dataInicio,
        LocalDate dataFim,
        BigDecimal entradas,
        BigDecimal saidas,
        BigDecimal liquido,
        BigDecimal disponivel,
        BigDecimal bloqueado,
        BigDecimal aReceber,
        BigDecimal comprometido,
        List<ReservaAbertaResponse> reservasAbertas,
        List<TotalPorTipoResponse> porTipo) {
}
