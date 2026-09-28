package com.motoshift.service.fiscal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A chave de acesso de 50 dígitos da NFS-e nacional — posição por posição.
 *
 * O que estes testes prendem é o formato oficial, que o DANFSe mostra no
 * topo: cMun(7) + ambGer(1) + tpInsc(1) + inscrição(14) + nNFSe(13) +
 * AAMM(4) + cNum(9) + DV(1). Uma posição a mais ou a menos e a chave "parece"
 * certa na tela mas não é a do padrão.
 */
class ChaveDeAcessoNfseTest {

    private static final LocalDateTime AGOSTO_2026 = LocalDateTime.of(2026, 8, 15, 9, 30);

    @Test
    @DisplayName("tem 50 dígitos, cada campo na posição do padrão nacional")
    void composicao() {
        String chave = ChaveDeAcessoNfse.gerar("4106902", ChaveDeAcessoNfse.INSCRICAO_CNPJ,
                "12.345.678/0001-90", 12, AGOSTO_2026, "semente");

        assertThat(chave).hasSize(50).containsOnlyDigits();
        assertThat(chave.substring(0, 7)).isEqualTo("4106902");         // município IBGE
        assertThat(chave.charAt(7)).isEqualTo('2');                     // Sistema Nacional
        assertThat(chave.charAt(8)).isEqualTo('2');                     // CNPJ
        assertThat(chave.substring(9, 23)).isEqualTo("12345678000190"); // inscrição
        assertThat(chave.substring(23, 36)).isEqualTo("0000000000012"); // número da NFS-e
        assertThat(chave.substring(36, 40)).isEqualTo("2608");          // AAMM da emissão
        assertThat(ChaveDeAcessoNfse.valida(chave)).isTrue();
    }

    @Test
    @DisplayName("o entregador sem CPF no cadastro entra com zeros, e não com a CNH")
    void semCpf() {
        String chave = ChaveDeAcessoNfse.gerar("4106902", ChaveDeAcessoNfse.INSCRICAO_CPF,
                null, 1, AGOSTO_2026, "semente");

        assertThat(chave.charAt(8)).isEqualTo('1');
        assertThat(chave.substring(9, 23)).isEqualTo("00000000000000");
        assertThat(ChaveDeAcessoNfse.valida(chave)).isTrue();
    }

    @Test
    @DisplayName("a mesma nota gera a mesma chave; outra semente, outro código numérico")
    void deterministica() {
        String a = ChaveDeAcessoNfse.gerar("4106902", 1, null, 7, AGOSTO_2026, "nota-a");
        String deNovo = ChaveDeAcessoNfse.gerar("4106902", 1, null, 7, AGOSTO_2026, "nota-a");
        String b = ChaveDeAcessoNfse.gerar("4106902", 1, null, 7, AGOSTO_2026, "nota-b");

        assertThat(deNovo).isEqualTo(a);
        assertThat(b.substring(40, 49)).isNotEqualTo(a.substring(40, 49));
    }

    @Test
    @DisplayName("DV em módulo 11, pesos 2 a 9 — confere com o exemplo do manual da NF-e")
    void digitoVerificador() {
        // O exemplo de cálculo do DV do Manual de Orientação do Contribuinte
        // da NF-e: soma 644, resto 6, DV 5. A NFS-e nacional usa a mesma regra.
        assertThat(ChaveDeAcessoNfse.digitoVerificador(
                "5206043300991100250655012000000780026730161")).isEqualTo(5);
    }

    @Test
    @DisplayName("uma chave adulterada não confere")
    void adulterada() {
        String chave = ChaveDeAcessoNfse.gerar("4106902", 1, null, 3, AGOSTO_2026, "x");
        int dv = chave.charAt(49) - '0';
        String adulterada = chave.substring(0, 49) + (dv + 1) % 10;

        assertThat(ChaveDeAcessoNfse.valida(adulterada)).isFalse();
        assertThat(ChaveDeAcessoNfse.valida("123")).isFalse();
        assertThat(ChaveDeAcessoNfse.valida(null)).isFalse();
    }
}
