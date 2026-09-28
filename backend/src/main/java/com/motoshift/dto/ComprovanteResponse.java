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
 *
 * <p>Os três últimos campos vêm do modelo legal de cada documento:
 * {@code valorPorExtenso} é o que todo recibo repete ao lado do número, nulo
 * nos que não são recibo;
 * {@code fundamento} diz de onde vem o modelo ("Código Civil, art. 320" no
 * recibo, o Regulamento Pix no comprovante de Pix), nulo quando não há modelo
 * legal; {@code declaracao} é o texto de quitação do recibo, nulo nos outros.
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
        List<Linha> detalhes,
        String valorPorExtenso,
        String fundamento,
        String declaracao) {

    /** Uma linha "rótulo: valor" do corpo do comprovante. */
    public record Linha(String rotulo, String valor) {}
}
