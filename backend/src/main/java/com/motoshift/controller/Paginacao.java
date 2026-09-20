package com.motoshift.controller;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;

import java.util.List;

/**
 * Paginação opcional das listagens.
 *
 * O contrato é o mesmo em todas as rotas: {@code ?pagina=0&tamanho=20}. Sem
 * {@code pagina}, a rota devolve a lista inteira, como sempre fez — o app em
 * produção não manda os parâmetros e não pode quebrar. Com {@code pagina}, a
 * resposta continua sendo um array JSON (o mesmo formato de antes) e o total
 * vai no header {@code X-Total-Count}, para o cliente saber quando parar.
 *
 * O teto de tamanho existe porque "página" sem limite é só a lista inteira com
 * outro nome.
 */
final class Paginacao {

    static final String TOTAL = "X-Total-Count";
    static final int TAMANHO_PADRAO = 20;
    static final int TAMANHO_MAXIMO = 100;

    private Paginacao() {}

    /** O pedido de página, ou null quando a chamada não pediu paginação. */
    static Pageable pedido(Integer pagina, Integer tamanho) {
        if (pagina == null) return null;
        int t = tamanho == null ? TAMANHO_PADRAO : Math.min(Math.max(tamanho, 1), TAMANHO_MAXIMO);
        return PageRequest.of(Math.max(pagina, 0), t);
    }

    static <T> ResponseEntity<List<T>> resposta(Page<T> pagina) {
        return ResponseEntity.ok()
                .header(TOTAL, String.valueOf(pagina.getTotalElements()))
                .body(pagina.getContent());
    }

    /**
     * Para listagens que só existem em memória (filtros que o banco não faz):
     * fatia o resultado já filtrado e ordenado.
     */
    static <T> ResponseEntity<List<T>> fatia(List<T> tudo, Pageable pedido) {
        if (pedido == null) return ResponseEntity.ok(tudo);
        int de = (int) Math.min(pedido.getOffset(), tudo.size());
        int ate = Math.min(de + pedido.getPageSize(), tudo.size());
        return ResponseEntity.ok()
                .header(TOTAL, String.valueOf(tudo.size()))
                .body(tudo.subList(de, ate));
    }
}
