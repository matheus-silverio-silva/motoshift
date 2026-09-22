package com.motoshift.service.fiscal;

import com.motoshift.entity.Usuario;

/**
 * O CPF ou CNPJ de uma parte, como sai num documento: mascarado.
 *
 * <p><b>Por que mascarar.</b> O documento pode ser baixado, impresso e
 * encaminhado. O número inteiro não acrescenta nada à leitura — quem precisa
 * conferir a nota confere pelo código de verificação — e expõe um dado que a
 * LGPD pede para tratar com finalidade. A máscara segue o formato usual: CPF
 * {@code ***.456.789-**}, CNPJ {@code **.345.678/0001-**}.
 *
 * <p><b>O entregador não tem CPF cadastrado.</b> O cadastro dele pede a CNH, e
 * é a CNH que está em {@code documentoFederal}. Apresentar esse número no campo
 * "CPF" de um documento fiscal seria afirmar uma coisa falsa com cara de
 * verdadeira — os dois têm 11 dígitos. Por isso o documento do entregador sai
 * como CPF não informado, e a tela diz isso por extenso. Uma NFS-e real exigiria
 * o CPF (ou o CNPJ do MEI); coletá-lo é mudança de cadastro, fora deste escopo.
 *
 * @param tipo   "CPF" ou "CNPJ"
 * @param numero o número mascarado, ou {@code null} quando não há
 */
public record DocumentoDaParte(String tipo, String numero) {

    public static DocumentoDaParte de(Usuario u) {
        if (u == null) return new DocumentoDaParte("CPF", null);
        if ("lojista".equalsIgnoreCase(u.getTipo())) {
            return new DocumentoDaParte("CNPJ", mascarar(u.getDocumentoFederal()));
        }
        return new DocumentoDaParte("CPF", null);
    }

    /**
     * Mascara um CPF (11 dígitos) ou CNPJ (14 dígitos). Qualquer outra coisa
     * devolve {@code null}: um número que não se sabe o que é não vai para o
     * documento.
     */
    public static String mascarar(String documento) {
        if (documento == null) return null;
        String d = documento.replaceAll("[^0-9]", "");
        if (d.length() == 11) {
            return "***." + d.substring(3, 6) + "." + d.substring(6, 9) + "-**";
        }
        if (d.length() == 14) {
            return "**." + d.substring(2, 5) + "." + d.substring(5, 8) + "/"
                    + d.substring(8, 12) + "-**";
        }
        return null;
    }
}
