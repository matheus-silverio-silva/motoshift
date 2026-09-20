package com.motoshift.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Um relatório financeiro: os números apurados, e a leitura que a IA fez deles.
 *
 * <p><b>Os números vêm primeiro, e existem sem a IA.</b> Antes, o endpoint
 * montava um texto, mandava para o Claude e devolvia só a resposta dele — se a
 * chamada falhasse, a resposta era 503 e o usuário ficava sem nada, embora
 * todos os números já estivessem apurados. Agora a análise é um campo a mais:
 * quando a IA não responde, ele vem {@code null} e o relatório continua sendo
 * um relatório.
 *
 * @param perfil     "motoboy" ou "lojista"
 * @param periodo    rótulo legível, como "Setembro 2026" ou "01/09 a 30/09"
 * @param dataInicio primeiro dia apurado
 * @param dataFim    último dia apurado, inclusive
 * @param numeros    a apuração, com chaves estáveis — ver RelatorioService
 * @param series     quebras em lista: por lojista, por dia da semana, por faixa
 *                   de horário, por entregador
 * @param analise    o texto da IA, ou {@code null} quando ela não respondeu
 * @param relatorio  o mesmo texto de {@code analise}. @deprecated: é a chave que
 *                   o app em produção lê; sai quando ele migrar para
 *                   {@code analise}
 */
public record RelatorioFinanceiroResponse(
        String perfil,
        String periodo,
        LocalDate dataInicio,
        LocalDate dataFim,
        Map<String, Object> numeros,
        Map<String, List<ItemDeQuebra>> series,
        String analise,
        @Deprecated String relatorio) {

    public static RelatorioFinanceiroResponse de(String perfil, String periodo,
                                                 LocalDate inicio, LocalDate fim,
                                                 Map<String, Object> numeros,
                                                 Map<String, List<ItemDeQuebra>> series,
                                                 String analise) {
        return new RelatorioFinanceiroResponse(perfil, periodo, inicio, fim,
                numeros, series, analise, analise);
    }

    /**
     * Uma linha de quebra: um rótulo, um total e quantos lançamentos o
     * compõem.
     *
     * @param rotulo    "Pizzaria do Fernando", "Segunda", "18h - 22h"
     * @param total     soma em reais
     * @param quantidade quantos turnos ou lançamentos entraram
     */
    public record ItemDeQuebra(String rotulo, BigDecimal total, long quantidade) {
    }
}
