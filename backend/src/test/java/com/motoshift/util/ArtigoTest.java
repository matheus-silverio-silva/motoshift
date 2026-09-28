package com.motoshift.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ArtigoTest {

    @Test
    @DisplayName("os nomes da massa e os casos que a regra de terminação erraria")
    void artigos() {
        assertThat(Artigo.de("Hamburgueria da Cláudia")).isEqualTo("da");
        assertThat(Artigo.de("Pizzaria do Fernando")).isEqualTo("da");
        assertThat(Artigo.de("Farmácia Ana")).isEqualTo("da");
        assertThat(Artigo.de("Mercado Andrade")).isEqualTo("do");
        assertThat(Artigo.definido("Mercado Andrade")).isEqualTo("o");
        assertThat(Artigo.definido("Hamburgueria da Cláudia")).isEqualTo("a");
        assertThat(Artigo.de("Lanchonete Central")).isEqualTo("da");
        assertThat(Artigo.de("Café Paris")).isEqualTo("do");
        assertThat(Artigo.de("Padaria Universidade")).isEqualTo("da");
        assertThat(Artigo.de("Restaurante Sabor")).isEqualTo("do");
    }
}
