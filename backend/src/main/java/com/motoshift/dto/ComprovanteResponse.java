package com.motoshift.dto;

import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.service.fiscal.TipoDocumento;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Recibo ou comprovante de um lançamento que não é serviço prestado.
 *
 * <p>Não tem tabela: é derivado do lançamento toda vez que é pedido, e sai
 * igual toda vez — número a partir do id, código de autenticação por HMAC dos
 * campos do lançamento (ver {@code ComprovanteService}).
 */
public record ComprovanteResponse(
        TipoDocumento tipoDocumento,
        String titulo,
        String numero,
        String codigoAutenticacao,
        Long transacaoId,
        UUID operacaoId,
        TipoTransacao tipoLancamento,
        NaturezaTransacao natureza,
        BigDecimal valor,
        String descricao,
        LocalDateTime dataHora,
        String titularNome,
        String titularDocumentoTipo,
        String titularDocumento,
        String titularCidade,
        BigDecimal saldoDisponivelApos,
        BigDecimal saldoBloqueadoApos,
        List<Linha> detalhes) {

    /** Uma linha "rótulo: valor" do corpo do comprovante. */
    public record Linha(String rotulo, String valor) {}
}
