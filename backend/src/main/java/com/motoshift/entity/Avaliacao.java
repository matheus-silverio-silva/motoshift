package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "avaliacoes")
public class Avaliacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long turnoId;

    @Column(nullable = false)
    private Long avaliadorId;

    @Column(nullable = false)
    private Long avaliadoId;

    @Column(nullable = false)
    private Integer nota; // 1 a 5

    @Column(length = 100)
    private String comentario;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
    }

    public Long getId() { return id; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public Long getAvaliadorId() { return avaliadorId; }
    public void setAvaliadorId(Long avaliadorId) { this.avaliadorId = avaliadorId; }

    public Long getAvaliadoId() { return avaliadoId; }
    public void setAvaliadoId(Long avaliadoId) { this.avaliadoId = avaliadoId; }

    public Integer getNota() { return nota; }
    public void setNota(Integer nota) { this.nota = nota; }

    public String getComentario() { return comentario; }
    public void setComentario(String comentario) { this.comentario = comentario; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
