package com.motoshift.entity;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * Mapeia {@link StatusPagamento} para a coluna VARCHAR, no valor minúsculo que já
 * está gravado no banco.
 *
 * É converter e não {@code @Enumerated(EnumType.STRING)} porque aquele
 * persistiria {@code name()}, em MAIÚSCULO, sobre dados que dizem minúsculo.
 * Com {@code autoApply = true} ele vale para todo campo do tipo, sem anotação
 * em cada entidade — um campo novo de status de pagamento já nasce certo.
 */
@Converter(autoApply = true)
public class StatusPagamentoConverter implements AttributeConverter<StatusPagamento, String> {

    @Override
    public String convertToDatabaseColumn(StatusPagamento status) {
        return status == null ? null : status.getValor();
    }

    @Override
    public StatusPagamento convertToEntityAttribute(String valor) {
        return StatusPagamento.de(valor);
    }
}
