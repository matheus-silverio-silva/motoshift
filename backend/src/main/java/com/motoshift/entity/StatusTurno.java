package com.motoshift.entity;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Estados de um turno.
 *
 * O par constante/valor existe por um motivo concreto: a convenção Java pede
 * constante em MAIÚSCULO, e o banco e o JSON usam minúsculo desde o primeiro
 * dia. Persistir {@code name()} — o que {@code @Enumerated(EnumType.STRING)}
 * faria — gravaria "ABERTO" em cima de linhas que dizem "aberto" e quebraria
 * junto o app, que compara essas strings ao desserializar
 * ({@code Motoshift/lib/models/turno.dart}).
 *
 * Por isso o valor de persistência é explícito e sai daqui por dois caminhos
 * que nunca usam {@code name()}: {@link StatusTurnoConverter} para o banco e
 * {@link #getValor()} anotado com {@code @JsonValue} para a API.
 *
 * <p><b>EM_ANDAMENTO é lido, nunca escrito.</b> Nenhum ponto do backend chama
 * {@code setStatus} com ele; o estado é consultado pelo conflito de agenda
 * ({@code TurnoRepository.findConflitos}), pela contagem de turnos ativos do
 * lojista e pelo job de vencimento, e o app já sabe desenhá-lo. Ele espera o
 * check-in do entregador, que ainda não existe. Mantido no enum para que uma
 * linha legada com esse valor seja lida sem estourar.
 */
public enum StatusTurno {

    ABERTO("aberto"),
    ACEITO("aceito"),
    EM_ANDAMENTO("em_andamento"),
    FINALIZADO("finalizado"),
    CANCELADO("cancelado"),
    EXPIRADO("expirado");

    private final String valor;

    StatusTurno(String valor) {
        this.valor = valor;
    }

    /** O que vai para o banco e para o JSON — sempre minúsculo. */
    @JsonValue
    public String getValor() {
        return valor;
    }

    /**
     * Aceita o valor minúsculo. Devolve null para entrada nula, porque a
     * coluna admite null; valor desconhecido é erro alto e barulhento, e não
     * um null silencioso que só apareceria como bug três camadas adiante.
     */
    @JsonCreator
    public static StatusTurno de(String valor) {
        if (valor == null) return null;
        for (StatusTurno s : values()) {
            if (s.valor.equals(valor)) return s;
        }
        throw new IllegalArgumentException("Status de turno desconhecido: " + valor);
    }

    /** Turno encerrado: não aceita mais mudança de estado. */
    public boolean isEncerrado() {
        return this == FINALIZADO || this == CANCELADO;
    }
}
