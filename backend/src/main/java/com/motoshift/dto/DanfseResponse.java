package com.motoshift.dto;

import java.util.List;

/**
 * A NFS-e no leiaute do DANFSe — o Documento Auxiliar da NFS-e do padrão
 * nacional, na versão da NT SE/CGNFS-e nº 008/2026 (DANFSe v2.0). SIMULADO.
 *
 * <p><b>Por que o backend manda os quadros prontos.</b> O DANFSe é uma grade de
 * campos rotulados, em blocos numa ordem fixa — prestador, tomador,
 * destinatário, intermediário, serviço, tributação municipal, federal, IBS/CBS,
 * totais e informações complementares. Os rótulos são os do modelo oficial, e
 * as regras que decidem cada valor ("ISSQN retido?", "IBS/CBS se aplica nesta
 * competência?") são fiscais, não de tela. Montados aqui
 * ({@code LeiauteDanfse}), a tela e o PDF do app só desenham: não há como os
 * dois mostrarem rótulos diferentes, nem regra fiscal duplicada em Dart.
 *
 * <p>A identificação da nota (chave, número, competência, DPS) vem tipada,
 * porque o app a desenha de um jeito próprio — com o QR Code ao lado.
 *
 * @param versao             "DANFSe v2.0"
 * @param norma              a nota técnica que define o leiaute
 * @param chaveAcesso        50 dígitos, sem separadores
 * @param municipioEmissor   "Curitiba - PR"
 * @param codigoMunicipio    código IBGE de 7 dígitos
 * @param numeroDps          número da DPS (Declaração de Prestação de Serviço)
 * @param serieDps           série da DPS
 * @param conteudoQrCode     o que o QR Code carrega — ver {@code LeiauteDanfse}
 * @param avisoQrCode        o texto ao lado do QR Code
 * @param quadros            os blocos do documento, na ordem oficial
 */
public record DanfseResponse(
        String versao,
        String norma,
        String chaveAcesso,
        String municipioEmissor,
        String codigoMunicipio,
        Integer numeroDps,
        String serieDps,
        String conteudoQrCode,
        String avisoQrCode,
        List<Quadro> quadros) {

    /**
     * Um bloco do DANFSe.
     *
     * @param id         estável, para o app reconhecer o bloco (ex.: "prestador")
     * @param titulo     como o modelo oficial escreve
     * @param campos     a grade de campos; pode ser vazia
     * @param observacao texto corrido abaixo dos campos, ou o próprio conteúdo
     *                   do bloco quando não há campos ("intermediário não identificado")
     */
    public record Quadro(String id, String titulo, List<Campo> campos, String observacao) {}

    /**
     * Um campo: rótulo em cima, valor embaixo, como no documento oficial.
     *
     * @param largo    ocupa a linha inteira (descrição, endereço, nome)
     * @param destaque sombreado — a NT 008 manda destacar o valor líquido
     */
    public record Campo(String rotulo, String valor, boolean largo, boolean destaque) {

        public static Campo de(String rotulo, String valor) {
            return new Campo(rotulo, valor, false, false);
        }

        public static Campo largo(String rotulo, String valor) {
            return new Campo(rotulo, valor, true, false);
        }

        public static Campo destacado(String rotulo, String valor) {
            return new Campo(rotulo, valor, false, true);
        }
    }
}
