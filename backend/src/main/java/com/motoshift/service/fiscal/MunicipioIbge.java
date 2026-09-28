package com.motoshift.service.fiscal;

import java.text.Normalizer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * O código IBGE do município — o que a chave de acesso da NFS-e e o DANFSe
 * usam para dizer onde a nota foi emitida e onde o ISSQN incide.
 *
 * <p><b>Uma tabela curta, de propósito.</b> O cadastro guarda cidade e UF como
 * texto livre, e a tabela completa do IBGE tem 5.570 municípios. Aqui estão as
 * 27 capitais e a região de Curitiba, onde a massa de demonstração acontece.
 * Cidade fora da tabela sai com o código {@code 0000000} e o documento diz
 * "fora da tabela da simulação" — inventar um código seria afirmar um
 * município que talvez não seja o da pessoa. Numa emissão real o município
 * viria do cadastro fiscal, já codificado.
 */
public final class MunicipioIbge {

    /** O código de quem está fora da tabela: zeros, e não um palpite. */
    public static final String DESCONHECIDO = "0000000";

    private record Municipio(String nome, String uf, String codigo) {}

    private static final List<Municipio> TABELA = List.of(
            // Capitais
            new Municipio("Rio Branco", "AC", "1200401"),
            new Municipio("Maceió", "AL", "2704302"),
            new Municipio("Macapá", "AP", "1600303"),
            new Municipio("Manaus", "AM", "1302603"),
            new Municipio("Salvador", "BA", "2927408"),
            new Municipio("Fortaleza", "CE", "2304400"),
            new Municipio("Brasília", "DF", "5300108"),
            new Municipio("Vitória", "ES", "3205309"),
            new Municipio("Goiânia", "GO", "5208707"),
            new Municipio("São Luís", "MA", "2111300"),
            new Municipio("Cuiabá", "MT", "5103403"),
            new Municipio("Campo Grande", "MS", "5002704"),
            new Municipio("Belo Horizonte", "MG", "3106200"),
            new Municipio("Belém", "PA", "1501402"),
            new Municipio("João Pessoa", "PB", "2507507"),
            new Municipio("Curitiba", "PR", "4106902"),
            new Municipio("Recife", "PE", "2611606"),
            new Municipio("Teresina", "PI", "2211001"),
            new Municipio("Rio de Janeiro", "RJ", "3304557"),
            new Municipio("Natal", "RN", "2408102"),
            new Municipio("Porto Alegre", "RS", "4314902"),
            new Municipio("Porto Velho", "RO", "1100205"),
            new Municipio("Boa Vista", "RR", "1400100"),
            new Municipio("Florianópolis", "SC", "4205407"),
            new Municipio("São Paulo", "SP", "3550308"),
            new Municipio("Aracaju", "SE", "2800308"),
            new Municipio("Palmas", "TO", "1721000"),
            // Região de Curitiba
            new Municipio("São José dos Pinhais", "PR", "4125506"),
            new Municipio("Pinhais", "PR", "4119152"),
            new Municipio("Colombo", "PR", "4105805"),
            new Municipio("Araucária", "PR", "4101804"));

    private static final Map<String, Municipio> POR_NOME = new HashMap<>();
    private static final Map<String, Municipio> POR_CODIGO = new HashMap<>();

    static {
        for (Municipio m : TABELA) {
            POR_NOME.put(chave(m.nome(), m.uf()), m);
            POR_CODIGO.put(m.codigo(), m);
        }
    }

    private MunicipioIbge() {}

    /** O código de uma cidade/UF do cadastro, se estiver na tabela. */
    public static Optional<String> codigo(String cidade, String uf) {
        if (cidade == null || cidade.isBlank() || uf == null || uf.isBlank()) {
            return Optional.empty();
        }
        return Optional.ofNullable(POR_NOME.get(chave(cidade, uf))).map(Municipio::codigo);
    }

    /** O código, ou {@link #DESCONHECIDO}. */
    public static String codigoOuDesconhecido(String cidade, String uf) {
        return codigo(cidade, uf).orElse(DESCONHECIDO);
    }

    /**
     * "Curitiba - PR", como o DANFSe escreve o município de um código. É o que
     * deixa o município emissor preso à chave gravada na emissão, e não à
     * cidade que o perfil tiver hoje.
     */
    public static Optional<String> nome(String codigo) {
        return Optional.ofNullable(POR_CODIGO.get(codigo)).map(m -> m.nome() + " - " + m.uf());
    }

    /** Sem acento, minúsculo e com espaços simples: "São  José|pr" → "sao jose|PR". */
    private static String chave(String cidade, String uf) {
        String nome = Normalizer.normalize(cidade.trim(), Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .replaceAll("\\s+", " ")
                .toLowerCase();
        return nome + "|" + uf.trim().toUpperCase();
    }
}
