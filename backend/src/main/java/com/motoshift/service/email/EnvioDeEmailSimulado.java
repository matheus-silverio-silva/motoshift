package com.motoshift.service.email;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * "Envia" o e-mail escrevendo-o no log da aplicação.
 *
 * <p><b>O que ele simula, e por que isso basta.</b> O projeto não tem servidor
 * de e-mail, e o que precisa ser demonstrado não é a integração com um
 * provedor — é que a recuperação de senha não entrega o código a quem pediu
 * pela API: ele sai por outro canal, e só quem lê esse canal troca a senha.
 * Aqui o canal é o log do servidor (o console em dev, os logs do serviço no
 * Railway), que faz o papel da caixa de entrada.
 *
 * <p><b>O que isto significa em produção.</b> O código de recuperação aparece
 * em claro no log. É a consequência de simular o envio, não um descuido: quem
 * tem acesso ao log do servidor consegue redefinir a senha de uma conta com
 * pedido aberto, do mesmo jeito que conseguiria quem lesse a caixa de e-mail
 * dela. Por isso o banco guarda só o hash — o log é o ÚNICO lugar em que o
 * código existe —, e por isso esta classe é a primeira coisa a trocar quando
 * houver um provedor de verdade.
 *
 * <p>INFO de propósito: em nível mais baixo a "mensagem" sumiria com a
 * configuração de log de produção, e ninguém receberia o código.
 */
@Component
public class EnvioDeEmailSimulado implements EnvioDeEmail {

    private static final Logger log = LoggerFactory.getLogger(EnvioDeEmailSimulado.class);

    @Override
    public void enviar(String para, String assunto, String corpo) {
        log.info("[email-simulado] para: {} | assunto: {}\n{}", para, assunto, corpo);
    }
}
