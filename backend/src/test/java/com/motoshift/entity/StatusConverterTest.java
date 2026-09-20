package com.motoshift.entity;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * O contrato dos tres enums de status: o que vai para o banco é sempre
 * minúsculo, e nunca {@code name()}.
 *
 * É o teste que impede o erro clássico da migração para enum. Trocar os
 * converters por {@code @Enumerated(EnumType.STRING)} passaria em qualquer
 * outro teste da suíte — round-trip com maiúsculo funciona perfeitamente —
 * e só quebraria contra o banco de produção, que tem "aberto" gravado, e
 * contra o app, que compara essas strings ao desserializar.
 */
class StatusConverterTest {

    private final StatusTurnoConverter turnos = new StatusTurnoConverter();
    private final StatusInscricaoConverter inscricoes = new StatusInscricaoConverter();
    private final StatusPagamentoConverter pagamentos = new StatusPagamentoConverter();

    // ── O valor gravado é minúsculo, constante por constante ──────────────

    @ParameterizedTest
    @EnumSource(StatusTurno.class)
    @DisplayName("StatusTurno: grava minúsculo e volta na mesma constante")
    void statusTurno_roundTrip(StatusTurno status) {
        String gravado = turnos.convertToDatabaseColumn(status);

        assertThat(gravado).isEqualTo(gravado.toLowerCase());
        assertThat(gravado).isNotEqualTo(status.name());
        assertThat(turnos.convertToEntityAttribute(gravado)).isSameAs(status);
    }

    @ParameterizedTest
    @EnumSource(StatusInscricao.class)
    @DisplayName("StatusInscricao: grava minúsculo e volta na mesma constante")
    void statusInscricao_roundTrip(StatusInscricao status) {
        String gravado = inscricoes.convertToDatabaseColumn(status);

        assertThat(gravado).isEqualTo(gravado.toLowerCase());
        assertThat(gravado).isNotEqualTo(status.name());
        assertThat(inscricoes.convertToEntityAttribute(gravado)).isSameAs(status);
    }

    @ParameterizedTest
    @EnumSource(StatusPagamento.class)
    @DisplayName("StatusPagamento: grava minúsculo e volta na mesma constante")
    void statusPagamento_roundTrip(StatusPagamento status) {
        String gravado = pagamentos.convertToDatabaseColumn(status);

        assertThat(gravado).isEqualTo(gravado.toLowerCase());
        assertThat(gravado).isNotEqualTo(status.name());
        assertThat(pagamentos.convertToEntityAttribute(gravado)).isSameAs(status);
    }

    @ParameterizedTest
    @EnumSource(TipoTransacao.class)
    @DisplayName("TipoTransacao: grava minúsculo e volta na mesma constante")
    void tipoTransacao_roundTrip(TipoTransacao tipo) {
        TipoTransacaoConverter conv = new TipoTransacaoConverter();
        String gravado = conv.convertToDatabaseColumn(tipo);

        assertThat(gravado).isEqualTo(gravado.toLowerCase());
        assertThat(gravado).isNotEqualTo(tipo.name());
        assertThat(conv.convertToEntityAttribute(gravado)).isSameAs(tipo);
    }

    @ParameterizedTest
    @EnumSource(StatusTransacao.class)
    @DisplayName("StatusTransacao: grava minúsculo e volta na mesma constante")
    void statusTransacao_roundTrip(StatusTransacao status) {
        StatusTransacaoConverter conv = new StatusTransacaoConverter();
        String gravado = conv.convertToDatabaseColumn(status);

        assertThat(gravado).isEqualTo(gravado.toLowerCase());
        assertThat(gravado).isNotEqualTo(status.name());
        assertThat(conv.convertToEntityAttribute(gravado)).isSameAs(status);
    }

    @Test
    @DisplayName("os valores legados da transação não existem mais no enum — a V10 os reescreveu")
    void transacao_legadoNaoVolta() {
        // "turno" e "processado" eram as palavras antigas de pagamento_recebido
        // e concluido. Aceitá-los aqui reabriria as duas gerações de valor que
        // a V10 fechou; se um aparecer no banco, é erro alto.
        assertThatExceptionOfType(IllegalArgumentException.class)
                .isThrownBy(() -> TipoTransacao.de("turno"));
        assertThatExceptionOfType(IllegalArgumentException.class)
                .isThrownBy(() -> StatusTransacao.de("processado"));
        assertThat(TipoTransacao.PAGAMENTO_RECEBIDO.getValor()).isEqualTo("pagamento_recebido");
        assertThat(StatusTransacao.CONCLUIDO.getValor()).isEqualTo("concluido");
    }

    // ── Os valores exatos que já estão gravados no banco ──────────────────

    @Test
    @DisplayName("os valores de persistência são exatamente os que o banco e o app já usam")
    void valoresDePersistencia_saoOsDeHoje() {
        assertThat(StatusTurno.ABERTO.getValor()).isEqualTo("aberto");
        assertThat(StatusTurno.ACEITO.getValor()).isEqualTo("aceito");
        assertThat(StatusTurno.EM_ANDAMENTO.getValor()).isEqualTo("em_andamento");
        assertThat(StatusTurno.FINALIZADO.getValor()).isEqualTo("finalizado");
        assertThat(StatusTurno.CANCELADO.getValor()).isEqualTo("cancelado");
        assertThat(StatusTurno.EXPIRADO.getValor()).isEqualTo("expirado");

        assertThat(StatusInscricao.ACEITO.getValor()).isEqualTo("aceito");
        assertThat(StatusInscricao.FINALIZADO.getValor()).isEqualTo("finalizado");
        assertThat(StatusInscricao.CANCELADO.getValor()).isEqualTo("cancelado");

        assertThat(StatusPagamento.PENDENTE.getValor()).isEqualTo("pendente");
        assertThat(StatusPagamento.PAGO.getValor()).isEqualTo("pago");
    }

    // ── null e desconhecido ───────────────────────────────────────────────

    @Test
    @DisplayName("null atravessa nos dois sentidos — pagamento_status é anulável")
    void null_atravessa() {
        assertThat(pagamentos.convertToDatabaseColumn(null)).isNull();
        assertThat(pagamentos.convertToEntityAttribute(null)).isNull();
        assertThat(turnos.convertToDatabaseColumn(null)).isNull();
        assertThat(turnos.convertToEntityAttribute(null)).isNull();
    }

    @Test
    @DisplayName("valor desconhecido no banco falha alto, em vez de virar null")
    void desconhecido_estoura() {
        assertThatExceptionOfType(IllegalArgumentException.class)
                .isThrownBy(() -> turnos.convertToEntityAttribute("congelado"))
                .withMessageContaining("congelado");

        // MAIUSCULO tambem e desconhecido: e o que @Enumerated(STRING) gravaria,
        // e o banco nunca deve ter isso.
        assertThatExceptionOfType(IllegalArgumentException.class)
                .isThrownBy(() -> turnos.convertToEntityAttribute("ABERTO"));
    }
}
