package com.motoshift.service.gateway;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Gateway de mentira, com comportamento de verdade.
 *
 * <p><b>O que ele simula, e por que isso importa.</b> Um TCC não tem credencial
 * de PSP, mas o que precisa ser demonstrado não é a integração com um banco — é
 * que o sistema trata dinheiro que entra e sai como algo que ele não controla:
 * a cobrança nasce pendente e só vira saldo quando alguém de fora confirma, e a
 * transferência pode ser recusada depois de o débito já ter acontecido. As duas
 * situações são reproduzidas aqui, e o ledger reage a elas do mesmo jeito que
 * reagiria a um provedor real.
 *
 * <p><b>Como forçar uma recusa.</b> Uma chave Pix que contenha
 * {@value #MARCADOR_DE_RECUSA} é recusada. Determinístico de propósito: uma
 * recusa aleatória deixaria o teste de estorno intermitente e a demonstração ao
 * vivo imprevisível. Quem quiser ver o estorno acontecendo cadastra a chave
 * {@code recusar@pix.com} e pede um saque.
 *
 * <p>O código copia-e-cola tem o formato do BR Code (EMV) para a tela poder
 * desenhar um QR de verdade, mas não é um Pix válido: nenhum app de banco vai
 * aceitá-lo, que é exatamente o que se quer de uma simulação.
 */
@Component
public class GatewayPagamentoSimulado implements GatewayPagamento {

    private static final Logger log = LoggerFactory.getLogger(GatewayPagamentoSimulado.class);

    /** Chave Pix contendo este texto é sempre recusada — o gancho da demonstração. */
    public static final String MARCADOR_DE_RECUSA = "recusar";

    @Override
    public CobrancaPix criarCobrancaPix(Long usuarioId, BigDecimal valor) {
        String referencia = "sim-" + UUID.randomUUID();
        log.info("[gateway-simulado] cobranca Pix de {} aberta para o usuario {} ({})",
                valor, usuarioId, referencia);
        return new CobrancaPix(brCodeFicticio(referencia, valor), valor, referencia);
    }

    @Override
    public ResultadoTransferencia transferirPix(String chavePix, BigDecimal valor, String referencia) {
        if (chavePix != null && chavePix.toLowerCase().contains(MARCADOR_DE_RECUSA)) {
            log.info("[gateway-simulado] transferencia {} recusada (chave de demonstracao)", referencia);
            return ResultadoTransferencia.recusa(
                    "O banco recusou a transferência para esta chave Pix.");
        }
        log.info("[gateway-simulado] transferencia {} de {} aprovada para {}",
                referencia, valor, chavePix);
        return ResultadoTransferencia.ok();
    }

    /**
     * Uma string no formato do BR Code, com os campos que o padrão exige.
     *
     * <p>Formato válido, conteúdo inventado: serve para a tela renderizar um QR
     * e para o botão de copiar ter o que copiar. O CRC no fim é fixo, e é o
     * primeiro campo que um app de banco de verdade rejeitaria.
     */
    private static String brCodeFicticio(String referencia, BigDecimal valor) {
        String chave = "motoshift-demo@pix.simulado";
        return "00020126"
                + "0014BR.GOV.BCB.PIX"
                + "01" + String.format("%02d", chave.length()) + chave
                + "52040000"
                + "5303986"
                + "54" + String.format("%02d", valor.toPlainString().length()) + valor.toPlainString()
                + "5802BR"
                + "5909MOTOSHIFT"
                + "6008CURITIBA"
                + "62" + String.format("%02d", referencia.length() + 4)
                + "05" + String.format("%02d", referencia.length()) + referencia
                + "6304FFFF";
    }
}
