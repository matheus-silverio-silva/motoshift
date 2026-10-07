package com.motoshift.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * A DRE simplificada de um período — a resposta de {@code GET /api/financeiro/dre}.
 *
 * <p>As chaves são estáveis: o app e o PDF as leem. O que muda de um papel
 * para o outro é a lista de {@link #linhas} e o mapa de {@link #indicadores};
 * a forma é a mesma.
 *
 * @param papel              "motoboy" ou "lojista" — sai do token
 * @param dataInicio         primeiro dia apurado
 * @param dataFim            último dia apurado, inclusive
 * @param linhas             a demonstração, de cima para baixo
 * @param resultado          a última linha: positivo, negativo ou zero
 * @param situacao           "lucro", "prejuizo" ou "equilibrio"
 * @param indicadores        números derivados; uma chave pode vir {@code null}
 *                           quando a conta não existe (margem sem receita)
 * @param anterior           o período imediatamente anterior, do mesmo tamanho
 * @param variacaoResultado  resultado deste período menos o do anterior, em
 *                           REAIS. Não é percentual de propósito: variação
 *                           percentual sobre resultado negativo engana — de
 *                           −100 para −50 "melhora 50%", de −100 para +100
 *                           daria "−200%"
 * @param lancamentosManuais quantos lançamentos informados à mão entraram na
 *                           conta. Zero quer dizer que o resultado só conhece
 *                           o que passou pela plataforma
 */
public record DreResponse(
        String papel,
        LocalDate dataInicio,
        LocalDate dataFim,
        List<Linha> linhas,
        BigDecimal resultado,
        String situacao,
        Map<String, Object> indicadores,
        Anterior anterior,
        BigDecimal variacaoResultado,
        int lancamentosManuais) {

    public static final String LUCRO = "lucro";
    public static final String PREJUIZO = "prejuizo";
    public static final String EQUILIBRIO = "equilibrio";

    /** Lucro acima de zero, prejuízo abaixo, equilíbrio no zero exato. */
    public static String situacaoDe(BigDecimal resultado) {
        int sinal = resultado == null ? 0 : resultado.signum();
        return sinal > 0 ? LUCRO : sinal < 0 ? PREJUIZO : EQUILIBRIO;
    }

    /**
     * Uma linha da demonstração.
     *
     * @param chave   identificador estável ("receita_bruta", "combustivel")
     * @param rotulo  o texto para a tela
     * @param valor   sempre a magnitude nas linhas comuns; nos subtotais e no
     *                resultado, o valor com sinal (um prejuízo é negativo)
     * @param tipo    "linha", "subtotal" ou "resultado"
     * @param origem  "extrato" (a plataforma registrou), "manual" (o usuário
     *                informou) ou "calculado" (soma das de cima)
     * @param subtrai {@code true} nas linhas que se tiram da de cima — as que a
     *                tela mostra com "(−)"
     */
    public record Linha(String chave, String rotulo, BigDecimal valor, String tipo,
                        String origem, boolean subtrai) {

        public static final String LINHA = "linha";
        public static final String SUBTOTAL = "subtotal";
        public static final String RESULTADO = "resultado";

        public static final String EXTRATO = "extrato";
        public static final String MANUAL = "manual";
        public static final String CALCULADO = "calculado";
    }

    /** O período de comparação: só o que a tela precisa dele. */
    public record Anterior(LocalDate dataInicio, LocalDate dataFim,
                           BigDecimal resultado, String situacao) {
    }

    /**
     * Um mês do gráfico anual — {@code GET /api/financeiro/dre/mensal}.
     *
     * @param mes       1 a 12
     * @param rotulo    "Jan", "Fev", ...
     * @param receita   receita bruta (entregador) ou de entregas (lojista)
     * @param custos    tudo o que saiu da receita até o resultado
     * @param resultado receita menos custos
     */
    public record Mes(int mes, String rotulo, BigDecimal receita, BigDecimal custos,
                      BigDecimal resultado, String situacao) {
    }
}
