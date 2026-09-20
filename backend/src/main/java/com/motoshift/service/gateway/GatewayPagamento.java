package com.motoshift.service.gateway;

import java.math.BigDecimal;

/**
 * A fronteira entre o MotoShift e o dinheiro que existe fora dele.
 *
 * <p><b>Por que uma interface, num projeto que só tem uma implementação.</b>
 * Não é preparação especulativa para um provedor futuro: é onde a fronteira do
 * sistema fica visível. Tudo o que está abaixo desta linha é irreversível e não
 * acontece no nosso banco — um Pix que cai na conta de alguém não volta com um
 * ROLLBACK. Ter isso em um contrato de dois métodos deixa explícito o que o
 * MotoShift controla (carteiras, reservas, liquidação) e o que ele apenas pede.
 *
 * <p>A implementação deste trabalho é {@link GatewayPagamentoSimulado}: gera um
 * código Pix fictício e aceita ou recusa segundo uma regra determinística. Um
 * provedor real entra implementando esta interface, e nada no ledger muda.
 *
 * <p><b>O gateway nunca mexe em saldo.</b> Quem credita e debita é o
 * {@code LedgerService}; o gateway só responde "entrou" ou "saiu". Misturar os
 * dois é como um sistema financeiro perde o rastro de dinheiro.
 */
public interface GatewayPagamento {

    /**
     * Abre uma cobrança Pix para o usuário pagar.
     *
     * <p>Não credita nada: a cobrança nasce pendente e o dinheiro só entra na
     * carteira quando a confirmação chega — pelo webhook do provedor real, ou
     * pelo endpoint que o simula.
     */
    CobrancaPix criarCobrancaPix(Long usuarioId, BigDecimal valor);

    /**
     * Envia um Pix para uma chave.
     *
     * <p>Síncrono de propósito neste projeto: o resultado volta na hora e o
     * saque é concluído ou estornado dentro da mesma requisição. Num provedor
     * real isto vira assíncrono, e a resposta passa a ser "aceito para
     * processamento" — a coluna {@code status} de {@code cobrancas} já prevê
     * esse estado intermediário.
     */
    ResultadoTransferencia transferirPix(String chavePix, BigDecimal valor, String referencia);

    /**
     * O que o provedor respondeu sobre uma transferência.
     *
     * @param aprovada true quando o dinheiro saiu
     * @param motivo   por que não saiu — texto para o extrato e para o log
     */
    record ResultadoTransferencia(boolean aprovada, String motivo) {

        public static ResultadoTransferencia ok() {
            return new ResultadoTransferencia(true, null);
        }

        public static ResultadoTransferencia recusa(String motivo) {
            return new ResultadoTransferencia(false, motivo);
        }
    }
}
