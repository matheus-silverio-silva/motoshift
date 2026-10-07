package com.motoshift.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Corpo de {@code POST} e {@code PUT /api/financeiro/lancamentos}.
 *
 * <p>De quem é o lançamento, diz o token. A categoria vem como texto, e não
 * como o enum: um valor desconhecido tem de virar um 400 com mensagem legível
 * pelo serviço, e não um erro de desserialização que o app não saberia
 * mostrar.
 */
public class LancamentoGerencialRequest {

    @NotBlank(message = "Informe a categoria")
    private String categoria;

    @NotNull(message = "Informe o valor")
    @DecimalMin(value = "0.01", message = "O valor deve ser maior que zero")
    @Digits(integer = 10, fraction = 2, message = "Valor inválido: use até duas casas decimais")
    private BigDecimal valor;

    @NotNull(message = "Informe a data")
    private LocalDate data;

    private boolean recorrente;

    private LocalDate recorrenteAte;

    private Long turnoId;

    @DecimalMin(value = "0.1", message = "Os quilômetros devem ser maiores que zero")
    @Digits(integer = 7, fraction = 1, message = "Quilômetros inválidos: use até uma casa decimal")
    private BigDecimal km;

    @Size(max = 200, message = "A descrição tem no máximo 200 caracteres")
    private String descricao;

    /**
     * Só no {@code PUT} de um recorrente (SCRUM-49): a partir de que dia os
     * dados novos valem. Com ele, o que já aconteceu antes continua com os
     * valores antigos — o lançamento é encerrado na véspera e um novo nasce
     * com os dados desta requisição. Sem ele, a edição corrige o histórico
     * inteiro. Ignorado no {@code POST}.
     */
    private LocalDate aplicarAPartirDe;

    public String getCategoria() { return categoria; }
    public void setCategoria(String categoria) {
        this.categoria = categoria == null ? null : categoria.trim();
    }

    public BigDecimal getValor() { return valor; }
    public void setValor(BigDecimal valor) { this.valor = valor; }

    public LocalDate getData() { return data; }
    public void setData(LocalDate data) { this.data = data; }

    public boolean isRecorrente() { return recorrente; }
    public void setRecorrente(boolean recorrente) { this.recorrente = recorrente; }

    public LocalDate getRecorrenteAte() { return recorrenteAte; }
    public void setRecorrenteAte(LocalDate recorrenteAte) { this.recorrenteAte = recorrenteAte; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public BigDecimal getKm() { return km; }
    public void setKm(BigDecimal km) { this.km = km; }

    public String getDescricao() { return descricao; }
    public void setDescricao(String descricao) { this.descricao = descricao; }

    public LocalDate getAplicarAPartirDe() { return aplicarAPartirDe; }
    public void setAplicarAPartirDe(LocalDate aplicarAPartirDe) { this.aplicarAPartirDe = aplicarAPartirDe; }
}
