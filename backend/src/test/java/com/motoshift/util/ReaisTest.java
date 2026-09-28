package com.motoshift.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Dinheiro escrito como vai num documento. O valor por extenso é o do recibo,
 * e os casos abaixo são os que as regras de concordância pegam: "um real",
 * "cem" e "cento e", "mil e cem" e "mil duzentos", "um milhão de reais".
 */
class ReaisTest {

    @Test
    @DisplayName("formata em reais e alíquota com duas casas")
    void formatar() {
        assertThat(Reais.formatar(new BigDecimal("1234.5"))).isEqualTo("R$ 1.234,50");
        assertThat(Reais.formatar(null)).isEqualTo("R$ 0,00");
        assertThat(Reais.percentual(new BigDecimal("0.05"))).isEqualTo("5,00%");
        assertThat(Reais.percentual(new BigDecimal("0.015"))).isEqualTo("1,50%");
        assertThat(Reais.percentual(new BigDecimal("0.009"))).isEqualTo("0,90%");
    }

    @Test
    @DisplayName("por extenso, com as concordâncias do português")
    void porExtenso() {
        assertThat(extenso("1")).isEqualTo("um real");
        assertThat(extenso("0.01")).isEqualTo("um centavo");
        assertThat(extenso("0.50")).isEqualTo("cinquenta centavos");
        assertThat(extenso("1.05")).isEqualTo("um real e cinco centavos");
        assertThat(extenso("100")).isEqualTo("cem reais");
        assertThat(extenso("120")).isEqualTo("cento e vinte reais");
        assertThat(extenso("500")).isEqualTo("quinhentos reais");
        assertThat(extenso("1000")).isEqualTo("mil reais");
        assertThat(extenso("1100")).isEqualTo("mil e cem reais");
        assertThat(extenso("1234.56"))
                .isEqualTo("mil duzentos e trinta e quatro reais e cinquenta e seis centavos");
        assertThat(extenso("2019")).isEqualTo("dois mil e dezenove reais");
        assertThat(extenso("1000000")).isEqualTo("um milhão de reais");
        assertThat(extenso("2500000")).isEqualTo("dois milhões e quinhentos mil reais");
        assertThat(extenso("1001000")).isEqualTo("um milhão e mil reais");
        assertThat(extenso("0")).isEqualTo("zero real");
    }

    private static String extenso(String valor) {
        return Reais.porExtenso(new BigDecimal(valor));
    }
}
