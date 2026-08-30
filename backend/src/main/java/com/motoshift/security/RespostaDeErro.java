package com.motoshift.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.dto.ErroResponse;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Escreve o corpo de erro dos pontos onde o Spring MVC ainda nao chegou —
 * filtro de token, entry point e access denied handler.
 *
 * Sem isto, 401 e 403 sairiam com corpo vazio e o app mostraria "Erro
 * desconhecido". O formato e o mesmo {@link ErroResponse} do
 * {@code ApiExceptionHandler} de proposito: o app le um objeto so, tenha o
 * erro nascido no filtro de seguranca ou dentro de um controller.
 */
@Component
public class RespostaDeErro {

    private final ObjectMapper json;

    public RespostaDeErro(ObjectMapper json) {
        this.json = json;
    }

    public void escrever(HttpServletResponse resp, int status, String codigo, String mensagem)
            throws IOException {

        resp.setStatus(status);
        resp.setContentType(MediaType.APPLICATION_JSON_VALUE);
        resp.setCharacterEncoding("UTF-8");

        json.writeValue(resp.getWriter(), ErroResponse.de(codigo, mensagem));
    }
}
