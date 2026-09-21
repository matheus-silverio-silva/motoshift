package com.motoshift.util;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * O que todo CSV exportado pela API precisa: campo que não quebra a planilha
 * nem vira fórmula.
 *
 * <p>Saiu do ExtratoService quando o informe de rendimentos passou a exportar
 * CSV também: a proteção contra injeção de fórmula é justamente o tipo de
 * código que não pode existir em duas cópias, uma delas desatualizada.
 */
public final class Csv {

    private Csv() {}

    /**
     * Neutraliza o que quebraria o CSV.
     *
     * <p>O ponto e vírgula e a quebra de linha desalinhariam as colunas; e um
     * campo que começa com =, +, - ou @ é executado como fórmula ao abrir a
     * planilha, o que transforma uma descrição de turno em código rodando na
     * máquina de quem baixou o arquivo.
     */
    public static String seguro(String texto) {
        if (texto == null) return "";
        String limpo = texto.replace(';', ',').replace('\n', ' ').replace('\r', ' ');
        if (!limpo.isEmpty() && "=+-@".indexOf(limpo.charAt(0)) >= 0) {
            return "'" + limpo;
        }
        return limpo;
    }

    /** Duas casas, ponto decimal, sem notação científica. */
    public static String decimal(BigDecimal v) {
        return v == null ? "" : v.setScale(2, RoundingMode.HALF_UP).toPlainString();
    }
}
