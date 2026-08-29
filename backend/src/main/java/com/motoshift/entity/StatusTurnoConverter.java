package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * Mapeia {@link StatusTurno} para a coluna VARCHAR, no valor minúsculo que já
 * está gravado no banco.
 *
 * É converter e não {@code @Enumerated(EnumType.STRING)} porque aquele
 * persistiria {@code name()}, em MAIÚSCULO, sobre dados que dizem minúsculo.
 * Com {@code autoApply = true} ele vale para todo campo do tipo, sem anotação
 * em cada entidade — um campo novo de status de turno já nasce certo.
 */
@Converter(autoApply = true)
public class StatusTurnoConverter implements AttributeConverter<StatusTurno, String> {

    @Override
    public String convertToDatabaseColumn(StatusTurno status) {
        return status == null ? null : status.getValor();
    }

    @Override
    public StatusTurno convertToEntityAttribute(String valor) {
        return StatusTurno.de(valor);
    }
}
