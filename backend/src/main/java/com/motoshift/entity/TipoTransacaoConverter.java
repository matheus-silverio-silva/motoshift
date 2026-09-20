package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/** Grava {@link TipoTransacao} no valor minúsculo da coluna — ver StatusTurnoConverter. */
@Converter(autoApply = true)
public class TipoTransacaoConverter implements AttributeConverter<TipoTransacao, String> {

    @Override
    public String convertToDatabaseColumn(TipoTransacao tipo) {
        return tipo == null ? null : tipo.getValor();
    }

    @Override
    public TipoTransacao convertToEntityAttribute(String valor) {
        return TipoTransacao.de(valor);
    }
}
