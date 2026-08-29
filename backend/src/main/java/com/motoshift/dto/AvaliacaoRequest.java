package com.motoshift.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Corpo do POST /api/avaliacoes.
 *
 * Substitui o {@code Map<String, Object>} que o controller recebia e destrinchava
 * na mao, com cast de Integer para Long e ifs de faixa. Como DTO anotado, a
 * validacao roda antes do metodo e o {@code ApiExceptionHandler} devolve qual
 * campo errou — coisa que a versao com Map nao tinha como informar.
 *
 * O {@code avaliadorId} que o app ainda envia nao existe aqui de proposito:
 * quem avalia e quem esta no token.
 */
public class AvaliacaoRequest {

    @NotNull(message = "Informe o turno da avaliação.")
    private Long turnoId;

    @NotNull(message = "Informe quem está sendo avaliado.")
    private Long avaliadoId;

    @NotNull(message = "A nota deve ser entre 1 e 5.")
    @Min(value = 1, message = "A nota deve ser entre 1 e 5.")
    @Max(value = 5, message = "A nota deve ser entre 1 e 5.")
    private Integer nota;

    @Size(max = 100, message = "Comentário deve ter no máximo 100 caracteres.")
    private String comentario;

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public Long getAvaliadoId() { return avaliadoId; }
    public void setAvaliadoId(Long avaliadoId) { this.avaliadoId = avaliadoId; }

    public Integer getNota() { return nota; }
    public void setNota(Integer nota) { this.nota = nota; }

    public String getComentario() { return comentario; }
    public void setComentario(String comentario) { this.comentario = comentario; }
}
