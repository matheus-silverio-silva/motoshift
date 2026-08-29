package com.motoshift.dto;

/**
 * Formato unico de erro da API.
 *
 * Antes cada rota lancava ResponseStatusException com um texto solto e o corpo
 * so chegava ao app porque {@code server.error.include-message=always} estava
 * ligado — ou seja, a mensagem de validacao dependia de uma propriedade de
 * configuracao, nao do contrato. Com o handler central o contrato passa a ser
 * este objeto.
 *
 * @param codigo   identificador estavel do tipo de erro, para o app decidir o
 *                 que fazer sem depender do texto (que muda e e traduzivel)
 * @param mensagem texto pronto para mostrar ao usuario
 * @param campo    qual campo do formulario errou; null quando nao se aplica
 */
public record ErroResponse(String codigo, String mensagem, String campo) {

    public static ErroResponse de(String codigo, String mensagem) {
        return new ErroResponse(codigo, mensagem, null);
    }
}
