package com.motoshift.entity;

import jakarta.persistence.*;

import java.io.Serializable;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * Um entregador que a loja marcou com o coração (V18).
 *
 * <p>O par (lojista, entregador) é a chave: a mesma loja não favorita o mesmo
 * entregador duas vezes, e quem garante é o banco, não o código.
 */
@Entity
@Table(name = "favoritos",
       indexes = @Index(name = "ix_favorito_motoboy", columnList = "motoboyId"))
@IdClass(Favorito.Chave.class)
public class Favorito {

    @Id
    private Long lojistaId;

    @Id
    private Long motoboyId;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    protected Favorito() {}

    public Favorito(Long lojistaId, Long motoboyId) {
        this.lojistaId = lojistaId;
        this.motoboyId = motoboyId;
    }

    @PrePersist
    private void prePersist() {
        if (criadoEm == null) criadoEm = LocalDateTime.now();
    }

    public Long getLojistaId() { return lojistaId; }
    public Long getMotoboyId() { return motoboyId; }
    public LocalDateTime getCriadoEm() { return criadoEm; }

    /** A massa de demonstração conta uma história com datas no passado. */
    public void setCriadoEm(LocalDateTime criadoEm) { this.criadoEm = criadoEm; }

    /** Chave composta (lojista, entregador). */
    public static class Chave implements Serializable {
        private Long lojistaId;
        private Long motoboyId;

        public Chave() {}

        public Chave(Long lojistaId, Long motoboyId) {
            this.lojistaId = lojistaId;
            this.motoboyId = motoboyId;
        }

        @Override
        public boolean equals(Object o) {
            return o instanceof Chave c
                    && Objects.equals(lojistaId, c.lojistaId)
                    && Objects.equals(motoboyId, c.motoboyId);
        }

        @Override
        public int hashCode() { return Objects.hash(lojistaId, motoboyId); }
    }
}
