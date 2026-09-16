package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/** Grava {@link StatusTransacao} no valor minúsculo da coluna — ver StatusTurnoConverter. */
@Converter(autoApply = true)
public class StatusTransacaoConverter implements AttributeConverter<StatusTransacao, String> {

    @Override
    public String convertToDatabaseColumn(StatusTransacao status) {
        return status == null ? null : status.getValor();
    }

    @Override
    public StatusTransacao convertToEntityAttribute(String valor) {
        return StatusTransacao.de(valor);
    }
}
