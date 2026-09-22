package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/** Grava {@link NaturezaTransacao} no valor minúsculo da coluna — ver StatusTurnoConverter. */
@Converter(autoApply = true)
public class NaturezaTransacaoConverter implements AttributeConverter<NaturezaTransacao, String> {

    @Override
    public String convertToDatabaseColumn(NaturezaTransacao natureza) {
        return natureza == null ? null : natureza.getValor();
    }

    @Override
    public NaturezaTransacao convertToEntityAttribute(String valor) {
        return NaturezaTransacao.de(valor);
    }
}
