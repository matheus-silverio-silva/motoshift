package com.motoshift.dto;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * Os filtros da lista de notas fiscais, como chegam na query string.
 *
 * <p>Mesmo desenho do {@link ExtratoFiltro}: cada campo é um parâmetro da API,
 * e as datas chegam como dia — o fim do intervalo inclui o dia inteiro.
 *
 * <ul>
 *   <li>{@code papel}: {@code prestador} (notas em que eu prestei) ou
 *       {@code tomador} (notas de serviços que eu tomei);</li>
 *   <li>{@code competenciaDe}/{@code competenciaAte}: período da DATA DO
 *       SERVIÇO, não da emissão — é o que o fisco pergunta;</li>
 *   <li>{@code status}: {@code emitida} ou {@code cancelada};</li>
 *   <li>{@code contraparteId}: o outro lado da nota;</li>
 *   <li>{@code turnoId}.</li>
 * </ul>
 */
public class NotaFiscalFiltro {

    private String papel;
    private LocalDate competenciaDe;
    private LocalDate competenciaAte;
    private String status;
    private Long contraparteId;
    private Long turnoId;

    public String getPapel() { return papel; }
    public void setPapel(String papel) { this.papel = papel; }

    public LocalDateTime getCompetenciaDe() {
        return competenciaDe == null ? null : competenciaDe.atStartOfDay();
    }

    /** Começo do dia SEGUINTE: a consulta usa {@code <}, então o dia final entra inteiro. */
    public LocalDateTime getCompetenciaAte() {
        return competenciaAte == null ? null : competenciaAte.plusDays(1).atStartOfDay();
    }

    public LocalDate getCompetenciaDeBruta() { return competenciaDe; }
    public LocalDate getCompetenciaAteBruta() { return competenciaAte; }
    public void setCompetenciaDe(LocalDate d) { this.competenciaDe = d; }
    public void setCompetenciaAte(LocalDate d) { this.competenciaAte = d; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public Long getContraparteId() { return contraparteId; }
    public void setContraparteId(Long contraparteId) { this.contraparteId = contraparteId; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }
}
