package com.motoshift.util;

import java.text.Normalizer;
import java.util.Locale;
import java.util.Set;

/**
 * "da Hamburgueria", "do Mercado": o artigo antes do nome de uma loja.
 *
 * <p>As notificações falam da loja pelo nome ("Você recebeu uma gorjeta da
 * Hamburgueria da Cláudia", "A Hamburgueria da Cláudia publicou um turno"), e
 * um artigo fixo erra metade das vezes — "da Mercado Andrade". A regra olha a
 * primeira palavra: terminada em "a" ou nos sufixos femininos comuns, ou numa
 * das exceções conhecidas, é feminina; o resto, masculino. Não é gramática
 * completa, é o bastante para os nomes de comércio que aparecem aqui.
 */
public final class Artigo {

    private static final Set<String> FEMININOS = Set.of(
            "lanchonete", "rede");
    private static final Set<String> MASCULINOS = Set.of("dia", "sistema", "cafe");

    private Artigo() {}

    /** "a" ou "o". */
    public static String definido(String nome) {
        return feminino(nome) ? "a" : "o";
    }

    /** "da" ou "do". */
    public static String de(String nome) {
        return feminino(nome) ? "da" : "do";
    }

    static boolean feminino(String nome) {
        if (nome == null || nome.isBlank()) return true; // "a loja"
        String primeira = Normalizer.normalize(nome.trim().split("\\s+")[0], Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .toLowerCase(Locale.ROOT);
        if (MASCULINOS.contains(primeira)) return false;
        if (FEMININOS.contains(primeira)) return true;
        return primeira.endsWith("a") || primeira.endsWith("ade")
                || primeira.endsWith("cao") || primeira.endsWith("gem");
    }
}
