package com.motoshift.dto;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.json.JsonTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O JSON que o app recebe, caractere por caractere.
 *
 * A migração para enum mexeu no tipo de {@code status} e
 * {@code pagamentoStatus}; o contrato com o Flutter não pode ter mudado junto.
 * O app compara essas strings ao desserializar
 * ({@code Motoshift/lib/models/turno.dart}) e os goldens dependem do resultado,
 * então qualquer maiúscula aqui aparece lá como turno sem status.
 *
 * Usa o ObjectMapper configurado pelo Spring (o mesmo do servidor, com
 * {@code write-dates-as-timestamps=false}) e não um {@code new ObjectMapper()},
 * que serializaria as datas como array numérico e testaria outra coisa.
 */
@JsonTest
@ActiveProfiles("test")
class TurnoResponseJsonTest {

    @Autowired
    private ObjectMapper json;

    @Test
    @DisplayName("o JSON de TurnoResponse é exatamente o de antes dos enums")
    void serializacao_naoMudou() throws Exception {
        String saida = json.writeValueAsString(TurnoResponse.from(turnoCompleto()));

        assertThat(saida).isEqualTo(
                "{\"id\":42,\"lojistId\":7,\"motoboyId\":9,\"titulo\":\"Turno Tarde\","
                + "\"descricao\":\"Entregas na regiao\",\"regiao\":\"Agua Verde\","
                + "\"dataInicio\":\"2026-07-01T18:00:00\",\"dataFim\":\"2026-07-01T22:00:00\","
                + "\"valorEstimado\":120.00,\"raioEntregaKm\":8.0,\"latitude\":-25.4284,"
                + "\"longitude\":-49.2733,\"endereco\":\"Rua Teste, 100\",\"distanciaKm\":null,"
                + "\"expiradoEm\":null,\"vagas\":2,\"vagasPreenchidas\":0,"
                + "\"status\":\"aceito\",\"pagamentoStatus\":\"pendente\","
                + "\"lojistaConfirmouEm\":\"2026-07-01T23:00:00\","
                + "\"motoboyConfirmouEm\":null,\"criadoEm\":null,\"atualizadoEm\":null}");
    }

    @Test
    @DisplayName("cada constante de status sai minúscula no JSON")
    void todasAsConstantes_saemMinusculas() throws Exception {
        for (StatusTurno status : StatusTurno.values()) {
            Turno t = turnoCompleto();
            t.setStatus(status);

            assertThat(json.writeValueAsString(TurnoResponse.from(t)))
                    .contains("\"status\":\"" + status.getValor() + "\"")
                    .doesNotContain(status.name());
        }

        for (StatusPagamento pago : StatusPagamento.values()) {
            Turno t = turnoCompleto();
            t.setPagamentoStatus(pago);

            assertThat(json.writeValueAsString(TurnoResponse.from(t)))
                    .contains("\"pagamentoStatus\":\"" + pago.getValor() + "\"");
        }
    }

    @Test
    @DisplayName("a leitura aceita o minúsculo que o app envia")
    void desserializacao_aceitaMinusculo() throws Exception {
        assertThat(json.readValue("\"em_andamento\"", StatusTurno.class))
                .isEqualTo(StatusTurno.EM_ANDAMENTO);
        assertThat(json.readValue("\"pago\"", StatusPagamento.class))
                .isEqualTo(StatusPagamento.PAGO);
    }

    private Turno turnoCompleto() {
        Turno t = new Turno();
        // id é gerado pelo JPA (sem setter); simula um turno já persistido.
        ReflectionTestUtils.setField(t, "id", 42L);
        t.setLojistId(7L);
        t.setMotoboyId(9L);
        t.setTitulo("Turno Tarde");
        t.setDescricao("Entregas na regiao");
        t.setRegiao("Agua Verde");
        t.setDataInicio(LocalDateTime.of(2026, 7, 1, 18, 0));
        t.setDataFim(LocalDateTime.of(2026, 7, 1, 22, 0));
        t.setValorEstimado(new BigDecimal("120.00"));
        t.setRaioEntregaKm(8.0);
        t.setLatitude(-25.4284);
        t.setLongitude(-49.2733);
        t.setEndereco("Rua Teste, 100");
        t.setVagas(2);
        t.setStatus(StatusTurno.ACEITO);
        t.setPagamentoStatus(StatusPagamento.PENDENTE);
        t.setLojistaConfirmouEm(LocalDateTime.of(2026, 7, 1, 23, 0));
        return t;
    }
}
