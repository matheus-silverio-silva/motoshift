package com.motoshift.service.fiscal;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;

/**
 * A chave de acesso de 50 dígitos da NFS-e no padrão nacional — SIMULADA.
 *
 * <p><b>A composição é a oficial</b> (Sistema Nacional NFS-e, a mesma que o
 * DANFSe da NT SE/CGNFS-e nº 008/2026 mostra no topo do documento):
 *
 * <pre>
 *   posição  tam.  campo
 *    1– 7     7    cMun      código IBGE do município emissor
 *    8        1    ambGer    ambiente gerador: 1 = prefeitura, 2 = Sistema Nacional
 *    9        1    tpInsc    tipo da inscrição federal: 1 = CPF, 2 = CNPJ
 *   10–23    14    inscrição federal do emitente (CPF com zeros à esquerda)
 *   24–36    13    nNFSe     número da NFS-e
 *   37–40     4    AAMM      ano e mês da emissão
 *   41–49     9    cNum      código numérico
 *   50        1    DV        dígito verificador, módulo 11
 * </pre>
 *
 * <p><b>O que é simulado.</b> Na nota real, quem gera a chave é o Sistema
 * Nacional, e o {@code cNum} é aleatório. Aqui a plataforma faz o papel do
 * Sistema Nacional ({@code ambGer = 2}) e o {@code cNum} sai de um hash dos
 * dados da nota — a mesma nota gera sempre a mesma chave, o que deixa a chave
 * conferível nos testes. O entregador não tem CPF no cadastro
 * ({@link DocumentoDaParte}): a inscrição dele vai com zeros, em vez de um
 * número que pareceria o CPF de alguém.
 *
 * <p>O DV segue o módulo 11 com pesos de 2 a 9, da direita para a esquerda —
 * a mesma regra da chave da NF-e —, com resto 0 ou 1 dando DV 0.
 */
public final class ChaveDeAcessoNfse {

    /** A plataforma faz o papel do Sistema Nacional NFS-e. */
    public static final int AMBIENTE_SISTEMA_NACIONAL = 2;
    public static final int INSCRICAO_CPF = 1;
    public static final int INSCRICAO_CNPJ = 2;

    private ChaveDeAcessoNfse() {}

    /**
     * Monta a chave com o DV.
     *
     * @param codigoMunicipio código IBGE de 7 dígitos (zeros quando fora da tabela)
     * @param tipoInscricao   {@link #INSCRICAO_CPF} ou {@link #INSCRICAO_CNPJ}
     * @param inscricao       CPF ou CNPJ, com ou sem pontuação; nulo vira zeros
     * @param numeroNfse      número da NFS-e
     * @param emissao         data da emissão — dá o AAMM
     * @param semente         o que torna o código numérico desta nota único
     */
    public static String gerar(String codigoMunicipio, int tipoInscricao, String inscricao,
                               long numeroNfse, LocalDateTime emissao, String semente) {
        String sem = digitos(codigoMunicipio, 7)
                + AMBIENTE_SISTEMA_NACIONAL
                + tipoInscricao
                + digitos(inscricao, 14)
                + String.format("%013d", numeroNfse)
                + String.format("%02d%02d", emissao.getYear() % 100, emissao.getMonthValue())
                + codigoNumerico(semente);
        return sem + digitoVerificador(sem);
    }

    /** Módulo 11, pesos 2..9 da direita para a esquerda; resto 0 ou 1 dá 0. */
    static int digitoVerificador(String semDv) {
        int soma = 0;
        int peso = 2;
        for (int i = semDv.length() - 1; i >= 0; i--) {
            soma += (semDv.charAt(i) - '0') * peso;
            peso = peso == 9 ? 2 : peso + 1;
        }
        int resto = soma % 11;
        return resto < 2 ? 0 : 11 - resto;
    }

    /** A chave confere: 50 dígitos e o último é o DV dos 49 anteriores. */
    public static boolean valida(String chave) {
        if (chave == null || !chave.matches("\\d{50}")) return false;
        return digitoVerificador(chave.substring(0, 49)) == chave.charAt(49) - '0';
    }

    /** O código IBGE do município emissor, que abre a chave. */
    public static String codigoMunicipio(String chave) {
        return chave.substring(0, 7);
    }

    /** Nove dígitos derivados da semente — no lugar do aleatório do Sistema Nacional. */
    static String codigoNumerico(String semente) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest(semente.getBytes(StandardCharsets.UTF_8));
            long n = 0;
            for (int i = 0; i < 8; i++) {
                n = (n << 8) | (hash[i] & 0xFF);
            }
            return String.format("%09d", Math.floorMod(n, 1_000_000_000L));
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 é obrigatório em toda JVM; se faltar, o ambiente está quebrado.
            throw new IllegalStateException("SHA-256 indisponível nesta JVM", e);
        }
    }

    /** Só os dígitos, com zeros à esquerda até o tamanho; o que sobrar à esquerda cai. */
    private static String digitos(String valor, int tamanho) {
        String d = valor == null ? "" : valor.replaceAll("[^0-9]", "");
        if (d.length() > tamanho) return d.substring(d.length() - tamanho);
        return "0".repeat(tamanho - d.length()) + d;
    }
}
