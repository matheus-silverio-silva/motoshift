package com.motoshift.util;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Dinheiro escrito como vai num documento: "R$ 1.234,56" e "mil duzentos e
 * trinta e quatro reais e cinquenta e seis centavos".
 *
 * <p>O valor por extenso é o do recibo: é ele que impede alguém de
 * transformar "R$ 10,00" em "R$ 100,00" com uma caneta, e por isso todo
 * modelo de recibo o repete ao lado do número.
 */
public final class Reais {

    private static final Locale PT_BR = Locale.forLanguageTag("pt-BR");

    private static final String[] UNIDADES = {
            "zero", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove",
            "dez", "onze", "doze", "treze", "quatorze", "quinze", "dezesseis", "dezessete",
            "dezoito", "dezenove"};
    private static final String[] DEZENAS = {
            "", "", "vinte", "trinta", "quarenta", "cinquenta", "sessenta", "setenta",
            "oitenta", "noventa"};
    private static final String[] CENTENAS = {
            "", "cento", "duzentos", "trezentos", "quatrocentos", "quinhentos", "seiscentos",
            "setecentos", "oitocentos", "novecentos"};
    // Índice = posição do grupo de três dígitos (0 = unidades).
    private static final String[] SINGULAR = {"", "mil", "milhão", "bilhão"};
    private static final String[] PLURAL = {"", "mil", "milhões", "bilhões"};

    private Reais() {}

    /** "R$ 1.234,56". Nulo vira "R$ 0,00". */
    public static String formatar(BigDecimal valor) {
        BigDecimal v = valor == null ? BigDecimal.ZERO : valor.setScale(2, RoundingMode.HALF_UP);
        return String.format(PT_BR, "R$ %,.2f", v);
    }

    /** 0.05 → "5,00%"; 0.015 → "1,50%" — alíquota como o DANFSe escreve. */
    public static String percentual(BigDecimal aliquota) {
        BigDecimal pct = (aliquota == null ? BigDecimal.ZERO : aliquota)
                .multiply(BigDecimal.valueOf(100)).setScale(2, RoundingMode.HALF_UP);
        return String.format(PT_BR, "%,.2f%%", pct);
    }

    /**
     * "cento e vinte reais", "um real e cinco centavos", "cinquenta centavos",
     * "um milhão de reais". Vai até a casa dos bilhões — um recibo daqui não
     * chega lá.
     */
    public static String porExtenso(BigDecimal valor) {
        BigDecimal v = (valor == null ? BigDecimal.ZERO : valor.abs()).setScale(2, RoundingMode.HALF_UP);
        long inteiro = v.longValue();
        int centavos = v.remainder(BigDecimal.ONE).movePointRight(2).intValue();

        if (inteiro == 0 && centavos == 0) return "zero real";

        StringBuilder sb = new StringBuilder();
        if (inteiro > 0) {
            sb.append(inteiroPorExtenso(inteiro));
            // "um milhão DE reais": o grupo das unidades e o dos milhares zerados.
            boolean redondoEmMilhao = inteiro >= 1_000_000 && inteiro % 1_000_000 == 0;
            sb.append(redondoEmMilhao ? " de " : " ");
            sb.append(inteiro == 1 ? "real" : "reais");
        }
        if (centavos > 0) {
            if (inteiro > 0) sb.append(" e ");
            sb.append(inteiroPorExtenso(centavos)).append(centavos == 1 ? " centavo" : " centavos");
        }
        return sb.toString();
    }

    /** Um número inteiro positivo por extenso: 1234 → "mil duzentos e trinta e quatro". */
    static String inteiroPorExtenso(long n) {
        if (n == 0) return UNIDADES[0];
        List<Integer> grupos = new ArrayList<>();
        for (long r = n; r > 0; r /= 1000) grupos.add((int) (r % 1000));

        StringBuilder sb = new StringBuilder();
        for (int i = grupos.size() - 1; i >= 0; i--) {
            int g = grupos.get(i);
            if (g == 0) continue;
            if (sb.length() > 0) {
                // "mil e cem", "mil e vinte" — mas "mil duzentos e trinta".
                sb.append(g < 100 || g % 100 == 0 ? " e " : " ");
            }
            // "mil", e não "um mil".
            if (!(i == 1 && g == 1)) sb.append(grupoPorExtenso(g));
            if (i > 0) {
                if (!(i == 1 && g == 1)) sb.append(' ');
                sb.append(g == 1 ? SINGULAR[i] : PLURAL[i]);
            }
        }
        return sb.toString();
    }

    /** De 1 a 999. */
    private static String grupoPorExtenso(int n) {
        if (n == 100) return "cem";
        int c = n / 100;
        int resto = n % 100;
        StringBuilder sb = new StringBuilder();
        if (c > 0) sb.append(CENTENAS[c]);
        if (resto > 0) {
            if (c > 0) sb.append(" e ");
            if (resto < 20) {
                sb.append(UNIDADES[resto]);
            } else {
                sb.append(DEZENAS[resto / 10]);
                if (resto % 10 > 0) sb.append(" e ").append(UNIDADES[resto % 10]);
            }
        }
        return sb.toString();
    }
}
