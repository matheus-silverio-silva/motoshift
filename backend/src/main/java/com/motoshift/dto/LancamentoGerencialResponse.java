package com.motoshift.dto;

import com.motoshift.entity.CategoriaLancamento;
import com.motoshift.entity.GrupoDre;
import com.motoshift.entity.LancamentoGerencial;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * Um lançamento gerencial, como a tela o mostra.
 *
 * @param categoria            valor estável da categoria ("combustivel")
 * @param rotuloDaCategoria    o nome para a tela ("Combustível")
 * @param grupo                em que grupo da DRE ele entra
 * @param soma                 {@code true} se é receita; {@code false} se é
 *                             custo, despesa ou dedução
 * @param valor                o valor de UMA ocorrência
 * @param ocorrenciasNoPeriodo quantas vezes ele conta no período consultado —
 *                             1 para o avulso, o número de meses para o
 *                             recorrente; nulo fora de uma listagem por período
 * @param valorNoPeriodo       {@code valor × ocorrenciasNoPeriodo}: o que este
 *                             lançamento pesa na DRE do período. É o que faz a
 *                             lista da tela somar o mesmo que a DRE acima dela
 */
public record LancamentoGerencialResponse(
        Long id,
        CategoriaLancamento categoria,
        String rotuloDaCategoria,
        GrupoDre grupo,
        boolean soma,
        BigDecimal valor,
        LocalDate data,
        boolean recorrente,
        LocalDate recorrenteAte,
        Long turnoId,
        BigDecimal km,
        String descricao,
        LocalDateTime criadoEm,
        LocalDateTime atualizadoEm,
        Integer ocorrenciasNoPeriodo,
        BigDecimal valorNoPeriodo) {

    public static LancamentoGerencialResponse de(LancamentoGerencial l) {
        return de(l, null);
    }

    public static LancamentoGerencialResponse de(LancamentoGerencial l, Integer ocorrencias) {
        CategoriaLancamento c = l.getCategoria();
        return new LancamentoGerencialResponse(
                l.getId(), c, c.getRotulo(), c.getGrupo(), c.getGrupo().somaAoResultado(),
                l.getValor(), l.getData(), l.isRecorrente(), l.getRecorrenteAte(),
                l.getTurnoId(), l.getKm(), l.getDescricao(),
                l.getCriadoEm(), l.getAtualizadoEm(),
                ocorrencias,
                ocorrencias == null ? null : l.getValor().multiply(BigDecimal.valueOf(ocorrencias)));
    }
}
