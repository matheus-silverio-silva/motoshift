package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "usuarios")
public class Usuario {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nome;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String telefone;

    // "lojista" | "motoboy"
    @Column(nullable = false)
    private String tipo;

    private String documentoFederal;

    private String fotoPerfil;

    // Senha armazenada em texto simples apenas para ambiente de dev/H2.
    // Em produção substitua por BCrypt + Spring Security.
    @Column(nullable = false)
    private String senha;

    @Column(nullable = false)
    private Double score = 5.0;

    private Double mediaAvaliacao;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        if (score == null) score = 5.0;
    }

    // --- Getters e Setters ---

    public Long getId() { return id; }

    public String getNome() { return nome; }
    public void setNome(String nome) { this.nome = nome; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getTelefone() { return telefone; }
    public void setTelefone(String telefone) { this.telefone = telefone; }

    public String getTipo() { return tipo; }
    public void setTipo(String tipo) { this.tipo = tipo; }

    public String getDocumentoFederal() { return documentoFederal; }
    public void setDocumentoFederal(String documentoFederal) { this.documentoFederal = documentoFederal; }

    public String getFotoPerfil() { return fotoPerfil; }
    public void setFotoPerfil(String fotoPerfil) { this.fotoPerfil = fotoPerfil; }

    public String getSenha() { return senha; }
    public void setSenha(String senha) { this.senha = senha; }

    public Double getScore() { return score; }
    public void setScore(Double score) { this.score = score; }

    public Double getMediaAvaliacao() { return mediaAvaliacao; }
    public void setMediaAvaliacao(Double mediaAvaliacao) { this.mediaAvaliacao = mediaAvaliacao; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
