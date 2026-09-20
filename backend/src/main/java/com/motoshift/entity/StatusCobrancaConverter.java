package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/** Grava {@link StatusCobranca} no valor minúsculo da coluna — ver StatusTurnoConverter. */
@Converter(autoApply = true)
public class StatusCobrancaConverter implements AttributeConverter<StatusCobranca, String> {

    @Override
    public String convertToDatabaseColumn(StatusCobranca status) {
        return status == null ? null : status.getValor();
    }

    @Override
    public StatusCobranca convertToEntityAttribute(String valor) {
        return StatusCobranca.de(valor);
    }
}
