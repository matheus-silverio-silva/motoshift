package com.motoshift.service;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

/**
 * O intervalo que um relatório apura, com os dois dias inclusive.
 *
 * <p>Sem datas, é o mês corrente até hoje — o recorte que o relatório sempre
 * teve, e que continua sendo o padrão. Morava dentro do {@code
 * RelatorioService}; saiu de lá quando a DRE ({@code DreService}) passou a
 * precisar do mesmo recorte: dois "mês corrente" escritos em dois lugares
 * acabariam discordando no dia 1º ou no dia 31.
 *
 * @param dataInicio primeiro dia apurado
 * @param dataFim    último dia apurado, inclusive
 * @param rotulo     "Setembro 2026" para o mês corrente, "01/09 a 30/09/2026"
 *                   para um intervalo informado
 */
public record Periodo(LocalDate dataInicio, LocalDate dataFim, String rotulo) {

    private static final String[] MESES = {
        "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    };

    public static Periodo de(LocalDate inicio, LocalDate fim) {
        if (inicio == null && fim == null) {
            LocalDate hoje = LocalDate.now();
            LocalDate primeiro = hoje.withDayOfMonth(1);
            return new Periodo(primeiro, hoje,
                    MESES[hoje.getMonthValue() - 1] + " " + hoje.getYear());
        }
        LocalDate de = inicio != null ? inicio : LocalDate.now().withDayOfMonth(1);
        LocalDate ate = fim != null ? fim : LocalDate.now();
        if (ate.isBefore(de)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A data final não pode ser anterior à inicial.");
        }
        return entre(de, ate);
    }

    /** Um intervalo já conferido — o período anterior, o mês de um gráfico. */
    public static Periodo entre(LocalDate de, LocalDate ate) {
        return new Periodo(de, ate, String.format("%02d/%02d a %02d/%02d/%d",
                de.getDayOfMonth(), de.getMonthValue(),
                ate.getDayOfMonth(), ate.getMonthValue(), ate.getYear()));
    }

    public LocalDateTime inicio() {
        return dataInicio.atStartOfDay();
    }

    /** Exclusivo: o dia final entra inteiro. */
    public LocalDateTime fim() {
        return dataFim.plusDays(1).atStartOfDay();
    }

    /** Quantos dias o período tem, contando os dois extremos. */
    public long dias() {
        return ChronoUnit.DAYS.between(dataInicio, dataFim) + 1;
    }

    /**
     * O período imediatamente anterior, com o MESMO número de dias.
     *
     * <p>Mesmo tamanho, e não "o mês passado": comparar os 7 primeiros dias de
     * outubro com setembro inteiro diria que o resultado despencou todo
     * começo de mês. Sete dias se comparam com os sete dias de antes.
     */
    public Periodo anterior() {
        LocalDate ate = dataInicio.minusDays(1);
        return entre(ate.minusDays(dias() - 1), ate);
    }
}
