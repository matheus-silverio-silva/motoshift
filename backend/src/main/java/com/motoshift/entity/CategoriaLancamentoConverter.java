package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/** Grava {@link CategoriaLancamento} no valor minúsculo da coluna — ver StatusTurnoConverter. */
@Converter(autoApply = true)
public class CategoriaLancamentoConverter implements AttributeConverter<CategoriaLancamento, String> {

    @Override
    public String convertToDatabaseColumn(CategoriaLancamento categoria) {
        return categoria == null ? null : categoria.getValor();
    }

    @Override
    public CategoriaLancamento convertToEntityAttribute(String valor) {
        return CategoriaLancamento.de(valor);
    }
}
