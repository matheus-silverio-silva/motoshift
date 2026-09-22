package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/** Grava {@link TipoCobranca} no valor minúsculo da coluna — ver StatusTurnoConverter. */
@Converter(autoApply = true)
public class TipoCobrancaConverter implements AttributeConverter<TipoCobranca, String> {

    @Override
    public String convertToDatabaseColumn(TipoCobranca tipo) {
        return tipo == null ? null : tipo.getValor();
    }

    @Override
    public TipoCobranca convertToEntityAttribute(String valor) {
        return TipoCobranca.de(valor);
    }
}
