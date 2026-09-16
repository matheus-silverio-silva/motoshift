package com.motoshift.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Um turno concluído que ainda não gerou nota — o que a tela oferece para
 * emitir. Um turno com várias vagas aparece uma vez por entregador.
 */
public class NotaFiscalPendenteResponse {

    private Long turnoId;
    private Long prestadorId;
    private String tituloTurno;
    private LocalDateTime dataInicio;
    private BigDecimal valorServico;

    /** O outro lado: o nome do entregador para o lojista, e vice-versa. */
    private String contraparteNome;

    /** "prestador" ou "tomador" — o papel de quem está pedindo. */
    private String papel;

    public NotaFiscalPendenteResponse(Long turnoId, Long prestadorId, String tituloTurno,
                                      LocalDateTime dataInicio, BigDecimal valorServico,
                                      String contraparteNome, String papel) {
        this.turnoId = turnoId;
        this.prestadorId = prestadorId;
        this.tituloTurno = tituloTurno;
        this.dataInicio = dataInicio;
        this.valorServico = valorServico;
        this.contraparteNome = contraparteNome;
        this.papel = papel;
    }

    public Long getTurnoId() { return turnoId; }
    public Long getPrestadorId() { return prestadorId; }
    public String getTituloTurno() { return tituloTurno; }
    public LocalDateTime getDataInicio() { return dataInicio; }
    public BigDecimal getValorServico() { return valorServico; }
    public String getContraparteNome() { return contraparteNome; }
    public String getPapel() { return papel; }
}
