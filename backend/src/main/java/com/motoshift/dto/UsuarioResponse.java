package com.motoshift.dto;

import com.motoshift.entity.Usuario;

import java.time.LocalDate;
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
    private Double mediaAvaliacao;
    private LocalDate dataNascimento;
    private String cidade;
    private String estado;
    private String cnhNumero;
    private String cnhCategoria;
    private LocalDate cnhValidade;
    private String veiculoModelo;
    private String veiculoPlaca;
    private Integer veiculoAno;
    private String veiculoCor;
    private String nomeFantasia;
    private String enderecoComercial;
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
        r.mediaAvaliacao = u.getMediaAvaliacao();
        r.dataNascimento = u.getDataNascimento();
        r.cidade = u.getCidade();
        r.estado = u.getEstado();
        r.cnhNumero = u.getCnhNumero();
        r.cnhCategoria = u.getCnhCategoria();
        r.cnhValidade = u.getCnhValidade();
        r.veiculoModelo = u.getVeiculoModelo();
        r.veiculoPlaca = u.getVeiculoPlaca();
        r.veiculoAno = u.getVeiculoAno();
        r.veiculoCor = u.getVeiculoCor();
        r.nomeFantasia = u.getNomeFantasia();
        r.enderecoComercial = u.getEnderecoComercial();
        r.criadoEm = u.getCriadoEm();
        return r;
    }

    public Long getId() { return id; }
    public String getNome() { return nome; }
    public String getEmail() { return email; }
    public String getTelefone() { return telefone; }
    public String getTipo() { return tipo; }
    public String getDocumentoFederal() { return documentoFederal; }
    public String getFotoPerfil() { return fotoPerfil; }
    public Double getScore() { return score; }
    public Double getMediaAvaliacao() { return mediaAvaliacao; }
    public LocalDate getDataNascimento() { return dataNascimento; }
    public String getCidade() { return cidade; }
    public String getEstado() { return estado; }
    public String getCnhNumero() { return cnhNumero; }
    public String getCnhCategoria() { return cnhCategoria; }
    public LocalDate getCnhValidade() { return cnhValidade; }
    public String getVeiculoModelo() { return veiculoModelo; }
    public String getVeiculoPlaca() { return veiculoPlaca; }
    public Integer getVeiculoAno() { return veiculoAno; }
    public String getVeiculoCor() { return veiculoCor; }
    public String getNomeFantasia() { return nomeFantasia; }
    public String getEnderecoComercial() { return enderecoComercial; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
}
