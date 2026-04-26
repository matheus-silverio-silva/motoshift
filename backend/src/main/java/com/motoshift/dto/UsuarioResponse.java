package com.motoshift.dto;

import com.motoshift.entity.Usuario;

import java.time.LocalDateTime;

public class UsuarioResponse {

    private Long id;
    private String nome;
    private String email;
    private String telefone;
    private String tipo;
    private String documentoFederal;
    private String fotoPerfil;
    private Double score;
    private LocalDateTime criadoEm;

    public static UsuarioResponse from(Usuario u) {
        UsuarioResponse r = new UsuarioResponse();
        r.id = u.getId();
        r.nome = u.getNome();
        r.email = u.getEmail();
        r.telefone = u.getTelefone();
        r.tipo = u.getTipo();
        r.documentoFederal = u.getDocumentoFederal();
        r.fotoPerfil = u.getFotoPerfil();
        r.score = u.getScore();
        r.criadoEm = u.getCriadoEm();
        return r;
    }

    // --- Getters ---

    public Long getId() { return id; }
    public String getNome() { return nome; }
    public String getEmail() { return email; }
    public String getTelefone() { return telefone; }
    public String getTipo() { return tipo; }
    public String getDocumentoFederal() { return documentoFederal; }
    public String getFotoPerfil() { return fotoPerfil; }
    public Double getScore() { return score; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
}
