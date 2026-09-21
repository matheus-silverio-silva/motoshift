package com.motoshift.service.fiscal;

import com.motoshift.entity.Usuario;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class DocumentoDaParteTest {

    @Test
    @DisplayName("CPF mostra só os seis do meio")
    void cpf() {
        assertThat(DocumentoDaParte.mascarar("12345678900")).isEqualTo("***.456.789-**");
        assertThat(DocumentoDaParte.mascarar("123.456.789-00")).isEqualTo("***.456.789-**");
    }

    @Test
    @DisplayName("CNPJ esconde os dois primeiros e os dígitos verificadores")
    void cnpj() {
        assertThat(DocumentoDaParte.mascarar("12.345.678/0001-90")).isEqualTo("**.345.678/0001-**");
    }

    @Test
    @DisplayName("o que não é CPF nem CNPJ não vai para o documento")
    void desconhecido() {
        assertThat(DocumentoDaParte.mascarar(null)).isNull();
        assertThat(DocumentoDaParte.mascarar("")).isNull();
        assertThat(DocumentoDaParte.mascarar("12345")).isNull();
    }

    @Test
    @DisplayName("a CNH do entregador nunca aparece no campo CPF")
    void entregadorSemCpf() {
        Usuario u = new Usuario();
        u.setTipo("motoboy");
        u.setDocumentoFederal("12345678900"); // é a CNH, e tem 11 dígitos como um CPF

        DocumentoDaParte doc = DocumentoDaParte.de(u);

        assertThat(doc.tipo()).isEqualTo("CPF");
        assertThat(doc.numero()).isNull();
    }

    @Test
    @DisplayName("o lojista sai com o CNPJ mascarado")
    void lojista() {
        Usuario u = new Usuario();
        u.setTipo("lojista");
        u.setDocumentoFederal("11222333000144");

        assertThat(DocumentoDaParte.de(u)).isEqualTo(new DocumentoDaParte("CNPJ", "**.222.333/0001-**"));
    }
}
