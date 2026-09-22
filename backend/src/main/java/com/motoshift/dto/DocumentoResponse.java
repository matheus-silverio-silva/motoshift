package com.motoshift.dto;

import com.motoshift.service.fiscal.TipoDocumento;

/**
 * O documento de um lançamento do extrato: uma NFS-e ou um comprovante.
 *
 * <p>Exatamente um de {@link #nota} e {@link #comprovante} vem preenchido,
 * conforme {@link #tipoDocumento}. A marca de simulação vai no próprio corpo:
 * qualquer cliente que mostre o documento recebe junto a frase que precisa
 * mostrar.
 */
public record DocumentoResponse(
        TipoDocumento tipoDocumento,
        Long transacaoId,
        boolean simulado,
        String marca,
        NotaFiscalResponse nota,
        ComprovanteResponse comprovante) {

    public static final String MARCA = "DOCUMENTO SIMULADO — SEM VALOR FISCAL";

    public static DocumentoResponse deNota(Long transacaoId, NotaFiscalResponse nota) {
        return new DocumentoResponse(TipoDocumento.NFSE, transacaoId, true, MARCA, nota, null);
    }

    public static DocumentoResponse deComprovante(ComprovanteResponse c) {
        return new DocumentoResponse(c.tipoDocumento(), c.transacaoId(), true, MARCA, null, c);
    }
}
