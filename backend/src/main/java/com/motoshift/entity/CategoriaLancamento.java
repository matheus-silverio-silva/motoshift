package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import java.util.Arrays;
import java.util.List;

/**
 * O que um lançamento gerencial é (V25) — e, com isso, de quem é e onde entra.
 *
 * <p>Cada categoria sabe duas coisas que a tabela não repete:
 *
 * <ul>
 *   <li>o <b>papel</b> a que pertence: combustível é custo de quem roda, taxa
 *       de entrega é receita de quem vende. Um lojista lançando combustível é
 *       erro de quem chamou, e o serviço recusa;
 *   <li>o <b>grupo da DRE</b> ({@link GrupoDre}), que decide em que linha o
 *       valor aparece e com que sinal.
 * </ul>
 *
 * <p>O DAS do MEI está em {@link GrupoDre#DEDUCAO}, e não nas despesas fixas,
 * embora o valor seja fixo por mês: é tributo sobre a atividade, e na DRE o
 * que é tributo sai antes de qualquer custo — a receita líquida é o que sobra
 * depois dele.
 *
 * <p>Mesmo padrão dos outros enums: o valor gravado é minúsculo e explícito,
 * nunca {@code name()} (ver {@link StatusTurno}). A lista bate com o CHECK
 * {@code ck_lancamento_gerencial_categoria} da V25.
 */
public enum CategoriaLancamento {

    // ── Entregador ───────────────────────────────────────────────────────
    COMBUSTIVEL("combustivel", "motoboy", GrupoDre.CUSTO_VARIAVEL, "Combustível"),
    MANUTENCAO("manutencao", "motoboy", GrupoDre.CUSTO_VARIAVEL, "Manutenção"),
    DAS_MEI("das_mei", "motoboy", GrupoDre.DEDUCAO, "DAS do MEI"),
    CELULAR_INTERNET("celular_internet", "motoboy", GrupoDre.DESPESA_FIXA, "Celular e internet"),
    SEGURO("seguro", "motoboy", GrupoDre.DESPESA_FIXA, "Seguro"),
    PARCELA_OU_ALUGUEL_VEICULO("parcela_ou_aluguel_veiculo", "motoboy", GrupoDre.DESPESA_FIXA,
            "Parcela ou aluguel do veículo"),
    OUTRA_DESPESA_ENTREGADOR("outra_despesa_entregador", "motoboy", GrupoDre.DESPESA_FIXA,
            "Outra despesa"),

    // ── Lojista ──────────────────────────────────────────────────────────
    TAXA_DE_ENTREGA_COBRADA("taxa_de_entrega_cobrada", "lojista", GrupoDre.RECEITA,
            "Taxa de entrega cobrada"),
    ENTREGA_FORA_DO_APP("entrega_fora_do_app", "lojista", GrupoDre.CUSTO_ENTREGA,
            "Entrega fora do app"),
    OUTRA_DESPESA_ENTREGA("outra_despesa_entrega", "lojista", GrupoDre.DESPESA_OPERACIONAL,
            "Outra despesa de entrega");

    private final String valor;
    private final String papel;
    private final GrupoDre grupo;
    private final String rotulo;

    CategoriaLancamento(String valor, String papel, GrupoDre grupo, String rotulo) {
        this.valor = valor;
        this.papel = papel;
        this.grupo = grupo;
        this.rotulo = rotulo;
    }

    @JsonValue
    public String getValor() {
        return valor;
    }

    /** "motoboy" ou "lojista" — o mesmo texto de {@code Usuario.tipo}. */
    public String getPapel() {
        return papel;
    }

    public GrupoDre getGrupo() {
        return grupo;
    }

    /** O nome que a tela mostra. */
    public String getRotulo() {
        return rotulo;
    }

    public boolean ehDoPapel(String tipoDeUsuario) {
        return papel.equals(tipoDeUsuario);
    }

    /** As categorias de um papel, na ordem em que a DRE dele as mostra. */
    public static List<CategoriaLancamento> doPapel(String tipoDeUsuario) {
        return Arrays.stream(values()).filter(c -> c.ehDoPapel(tipoDeUsuario)).toList();
    }

    @JsonCreator
    public static CategoriaLancamento de(String valor) {
        if (valor == null) return null;
        for (CategoriaLancamento c : values()) {
            if (c.valor.equals(valor)) return c;
        }
        throw new IllegalArgumentException("Categoria de lançamento desconhecida: " + valor);
    }
}
