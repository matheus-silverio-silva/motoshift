package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * Mapeia {@link StatusInscricao} para a coluna VARCHAR, no valor minúsculo que já
 * está gravado no banco.
 *
 * É converter e não {@code @Enumerated(EnumType.STRING)} porque aquele
 * persistiria {@code name()}, em MAIÚSCULO, sobre dados que dizem minúsculo.
 * Com {@code autoApply = true} ele vale para todo campo do tipo, sem anotação
 * em cada entidade — um campo novo de status de inscrição já nasce certo.
 */
@Converter(autoApply = true)
public class StatusInscricaoConverter implements AttributeConverter<StatusInscricao, String> {

    @Override
    public String convertToDatabaseColumn(StatusInscricao status) {
        return status == null ? null : status.getValor();
    }

    @Override
    public StatusInscricao convertToEntityAttribute(String valor) {
        return StatusInscricao.de(valor);
    }
}
