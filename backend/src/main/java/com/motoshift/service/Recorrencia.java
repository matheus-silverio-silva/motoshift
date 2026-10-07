package com.motoshift.service;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;

/**
 * Em que dias um lançamento recorrente acontece — a conta, e só ela.
 *
 * <p>A regra: uma vez por mês, no dia do mês da primeira data; se o mês for
 * mais curto, no último dia dele (uma conta que vence todo dia 31 vence em 28
 * de fevereiro, não some em fevereiro nem pula para março). Começa na
 * primeira data e vai até {@code ate}, inclusive — ou não acaba, se
 * {@code ate} for nulo.
 *
 * <p>Função pura, sem banco e sem relógio: recebe as datas e devolve as
 * ocorrências. É o que permite testar os cantos (dia 31 em fevereiro, período
 * de meio mês, recorrência que termina antes do período) sem montar cenário
 * nenhum, e é por isso que a DRE não precisa de uma linha gravada por mês.
 */
public final class Recorrencia {

    private Recorrencia() {}

    /**
     * As ocorrências que caem dentro de [{@code inicio}, {@code fim}], os dois
     * inclusive, em ordem.
     *
     * @param primeira o dia do primeiro pagamento — dita o dia do mês
     * @param ate      última data em que a recorrência ainda vale; nulo = sem fim
     */
    public static List<LocalDate> ocorrencias(LocalDate primeira, LocalDate ate,
                                              LocalDate inicio, LocalDate fim) {
        List<LocalDate> datas = new ArrayList<>();
        if (primeira == null || inicio == null || fim == null || fim.isBefore(inicio)) return datas;

        // O que vier primeiro: o fim do período ou o fim da recorrência.
        LocalDate limite = ate != null && ate.isBefore(fim) ? ate : fim;
        LocalDate desde = primeira.isAfter(inicio) ? primeira : inicio;
        if (limite.isBefore(desde)) return datas;

        int dia = primeira.getDayOfMonth();
        for (YearMonth mes = YearMonth.from(desde); !mes.isAfter(YearMonth.from(limite));
                mes = mes.plusMonths(1)) {
            LocalDate ocorrencia = mes.atDay(Math.min(dia, mes.lengthOfMonth()));
            if (!ocorrencia.isBefore(desde) && !ocorrencia.isAfter(limite)) {
                datas.add(ocorrencia);
            }
        }
        return datas;
    }

    /**
     * A primeira ocorrência de uma recorrência do dia {@code diaDoMes} que cai
     * em {@code aPartirDe} ou depois: neste mês, se o dia ainda não passou; no
     * mês seguinte, se já passou. Mês mais curto que o dia, último dia dele.
     */
    public static LocalDate primeiraAPartirDe(int diaDoMes, LocalDate aPartirDe) {
        YearMonth mes = YearMonth.from(aPartirDe);
        LocalDate neste = mes.atDay(Math.min(diaDoMes, mes.lengthOfMonth()));
        if (!neste.isBefore(aPartirDe)) return neste;
        YearMonth seguinte = mes.plusMonths(1);
        return seguinte.atDay(Math.min(diaDoMes, seguinte.lengthOfMonth()));
    }

    /** Quantas vezes acontece no período — o que a DRE multiplica pelo valor. */
    public static int vezes(LocalDate primeira, LocalDate ate, LocalDate inicio, LocalDate fim) {
        return ocorrencias(primeira, ate, inicio, fim).size();
    }
}
