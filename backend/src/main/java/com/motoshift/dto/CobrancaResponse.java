package com.motoshift.dto;

import com.motoshift.entity.Cobranca;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.TipoCobranca;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Uma recarga ou um saque, como o app os vê.
 *
 * <p>{@code codigoPix} é o copia-e-cola numa recarga e a chave de destino num
 * saque — o mesmo campo com os dois sentidos, porque é sempre "o Pix desta
 * operação". A tela sabe qual dos dois pelo {@code tipo}.
 */
public class CobrancaResponse {

    private Long id;
    private TipoCobranca tipo;
    private BigDecimal valor;
    private StatusCobranca status;
    private String codigoPix;
    private LocalDateTime criadaEm;
    private LocalDateTime concluidaEm;

    public static CobrancaResponse from(Cobranca c) {
        CobrancaResponse r = new CobrancaResponse();
        r.id = c.getId();
        r.tipo = c.getTipo();
        r.valor = CarteiraResponse.emReais(c.getValor());
        r.status = c.getStatus();
        r.codigoPix = c.getCodigoPix();
        r.criadaEm = c.getCriadaEm();
        r.concluidaEm = c.getConcluidaEm();
        return r;
    }

    public Long getId() { return id; }
    public TipoCobranca getTipo() { return tipo; }
    public BigDecimal getValor() { return valor; }
    public StatusCobranca getStatus() { return status; }
    public String getCodigoPix() { return codigoPix; }
    public LocalDateTime getCriadaEm() { return criadaEm; }
    public LocalDateTime getConcluidaEm() { return concluidaEm; }
}
