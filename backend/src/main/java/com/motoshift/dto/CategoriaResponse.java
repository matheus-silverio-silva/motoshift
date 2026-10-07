package com.motoshift.dto;

import com.motoshift.entity.CategoriaLancamento;
import com.motoshift.entity.GrupoDre;

/**
 * Uma categoria de lançamento gerencial, para o app montar o formulário.
 *
 * <p>O app não guarda a lista: pede a do papel de quem está logado. Categoria
 * nova no backend aparece no formulário sem versão nova do app — e o lojista
 * nunca chega a ver "Combustível".
 *
 * @param valor         o que volta no {@code categoria} do lançamento
 * @param rotulo        o nome para a tela
 * @param grupo         o grupo da DRE
 * @param rotuloDoGrupo o nome do grupo, para agrupar a lista
 * @param soma          {@code true} se é receita
 */
public record CategoriaResponse(String valor, String rotulo, GrupoDre grupo,
                                String rotuloDoGrupo, boolean soma) {

    public static CategoriaResponse de(CategoriaLancamento c) {
        return new CategoriaResponse(c.getValor(), c.getRotulo(), c.getGrupo(),
                c.getGrupo().getRotulo(), c.getGrupo().somaAoResultado());
    }
}
