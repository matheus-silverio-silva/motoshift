package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Em que altura da DRE um lançamento gerencial entra.
 *
 * <p>É o grupo que diz o sinal: {@link #RECEITA} soma, todos os outros
 * subtraem. Por isso a tabela não tem coluna "tipo" (receita ou despesa) e o
 * valor é sempre positivo — duas fontes para o mesmo sinal acabariam, um dia,
 * discordando.
 *
 * <p>Os três primeiros depois da receita são do entregador, na ordem em que a
 * DRE dele os desconta; os dois últimos, do lojista. Ver
 * {@code service.DreService}.
 */
public enum GrupoDre {

    /** Dinheiro que entrou fora da plataforma — hoje, só a taxa que a loja cobra do cliente. */
    RECEITA("receita", "Receita"),

    /** Sai da receita bruta: tributo sobre o faturamento (o DAS do MEI). */
    DEDUCAO("deducao", "Deduções"),

    /** Cresce com o trabalho: combustível e manutenção. */
    CUSTO_VARIAVEL("custo_variavel", "Custos variáveis"),

    /** Existe trabalhando ou não: celular, seguro, parcela. */
    DESPESA_FIXA("despesa_fixa", "Despesas fixas"),

    /** Entrega paga por fora do app — custo direto da operação da loja. */
    CUSTO_ENTREGA("custo_entrega", "Custo de entrega"),

    /** O resto do que a operação de entrega da loja consome. */
    DESPESA_OPERACIONAL("despesa_operacional", "Outras despesas");

    private final String valor;
    private final String rotulo;

    GrupoDre(String valor, String rotulo) {
        this.valor = valor;
        this.rotulo = rotulo;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    public String getRotulo() {
        return rotulo;
    }

    /** Só a receita soma ao resultado; o resto é o que se tira dela. */
    public boolean somaAoResultado() {
        return this == RECEITA;
    }
}
