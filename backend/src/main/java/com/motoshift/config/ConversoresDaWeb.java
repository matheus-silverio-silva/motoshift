package com.motoshift.config;

import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import org.springframework.context.annotation.Configuration;
import org.springframework.format.FormatterRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Os enums do extrato na query string, no mesmo formato em que saem no JSON.
 *
 * <p>O JSON já usava o valor minúsculo ({@code "saque"}, {@code "credito"}),
 * pelo {@code @JsonCreator} de cada enum — mas o filtro do extrato chega por
 * parâmetro de URL, e ali o Spring só conhecia {@code Enum.valueOf}, que espera
 * o nome da constante ({@code SAQUE}). O resultado era um 400 em todo
 * {@code ?tipos=saque} e {@code ?natureza=credito} que o app mandava: o filtro
 * por tipo e por entrada/saída do extrato — e a exportação com filtro — nunca
 * funcionaram pelo HTTP. Os testes do serviço passavam porque montavam o
 * filtro em Java, sem passar pela conversão.
 *
 * <p>Com o conversor, a lista separada por vírgula ({@code tipos=saque,estorno})
 * vira {@code List<TipoTransacao>} pelo próprio Spring, elemento a elemento.
 * Valor desconhecido continua sendo 400.
 */
@Configuration
public class ConversoresDaWeb implements WebMvcConfigurer {

    @Override
    public void addFormatters(FormatterRegistry registry) {
        registry.addConverter(String.class, TipoTransacao.class, v -> TipoTransacao.de(v.trim()));
        registry.addConverter(String.class, NaturezaTransacao.class, v -> NaturezaTransacao.de(v.trim()));
        registry.addConverter(String.class, StatusTransacao.class, v -> StatusTransacao.de(v.trim()));
    }
}
