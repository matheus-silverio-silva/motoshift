package com.motoshift.service.email;

/**
 * A fronteira entre o MotoShift e a caixa de entrada de alguém.
 *
 * <p>Mesma ideia do {@code GatewayPagamento}: o que está abaixo desta linha
 * não acontece no nosso banco e não se desfaz com ROLLBACK — um e-mail
 * enviado está enviado. Um contrato de um método deixa explícito o que o
 * sistema controla (gerar o código, guardar o hash, conferir) e o que ele
 * apenas pede a um terceiro (entregar a mensagem).
 *
 * <p>A implementação deste trabalho é {@link EnvioDeEmailSimulado}, que
 * escreve a mensagem no log. Um provedor real (SMTP, SES, Resend) entra
 * implementando esta interface, e nada no fluxo de senha muda.
 */
public interface EnvioDeEmail {

    /**
     * Envia uma mensagem de texto.
     *
     * <p>Quem chama não espera resposta: o fluxo de "esqueci minha senha"
     * responde 202 exista ou não a conta, então uma falha de entrega não pode
     * virar erro para o cliente — a implementação registra e segue.
     */
    void enviar(String para, String assunto, String corpo);
}
