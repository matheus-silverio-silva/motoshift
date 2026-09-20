package com.motoshift.entity;

import jakarta.persistence.*;
import org.hibernate.annotations.DynamicUpdate;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * Conta da plataforma — lojista ou entregador.
 *
 * {@code @DynamicUpdate} porque esta linha tem dois escritores que não se
 * conhecem: a edição de perfil (que salva a entidade inteira) e o controle de
 * tentativas de login (que só mexe em dois campos, por UPDATE direto). Com o
 * UPDATE de todas as colunas, que é o padrão do Hibernate, salvar o perfil logo
 * depois de um erro de senha regravaria o contador com o valor antigo.
 */
@Entity
@DynamicUpdate
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

    // Hash BCrypt, sempre. Cadastro e massa de demonstração passam pelo
    // PasswordEncoder, e a V9 converteu as contas antigas que ainda estavam em
    // texto puro — o login não aceita outro formato.
    @Column(nullable = false)
    private String senha;

    @Column(nullable = false)
    private Double score = 5.0;

    private Double mediaAvaliacao;

    // ── Dados pessoais ─────────────────────────────────────────
    private LocalDate dataNascimento;
    private String cidade;
    private String estado;

    // ── CNH e Veículo (motoboy) ────────────────────────────────
    private String cnhNumero;
    private String cnhCategoria;          // "A" | "AB"
    private LocalDate cnhValidade;

    private String veiculoModelo;         // ex: "Honda CG 160"
    private String veiculoPlaca;          // ex: "ABC-1D23"
    private Integer veiculoAno;
    private String veiculoCor;

    // ── Lojista ────────────────────────────────────────────────
    private String nomeFantasia;
    private String enderecoComercial;

    // ── RF01: bloqueio por tentativas de login ─────────────────
    // No banco, e não num mapa em memória: o bloqueio precisa sobreviver a um
    // redeploy, valer igual em todas as instâncias e só existir para contas que
    // existem (o mapa era indexado pelo e-mail digitado e crescia com qualquer
    // e-mail inventado). Escritos só pelos UPDATEs do UsuarioRepository.
    @Column(nullable = false)
    private Integer tentativasLogin = 0;

    private LocalDateTime bloqueadoAte;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        if (score == null) score = 5.0;
        if (tentativasLogin == null) tentativasLogin = 0;
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

    public LocalDate getDataNascimento() { return dataNascimento; }
    public void setDataNascimento(LocalDate dataNascimento) { this.dataNascimento = dataNascimento; }

    public String getCidade() { return cidade; }
    public void setCidade(String cidade) { this.cidade = cidade; }

    public String getEstado() { return estado; }
    public void setEstado(String estado) { this.estado = estado; }

    public String getCnhNumero() { return cnhNumero; }
    public void setCnhNumero(String cnhNumero) { this.cnhNumero = cnhNumero; }

    public String getCnhCategoria() { return cnhCategoria; }
    public void setCnhCategoria(String cnhCategoria) { this.cnhCategoria = cnhCategoria; }

    public LocalDate getCnhValidade() { return cnhValidade; }
    public void setCnhValidade(LocalDate cnhValidade) { this.cnhValidade = cnhValidade; }

    public String getVeiculoModelo() { return veiculoModelo; }
    public void setVeiculoModelo(String veiculoModelo) { this.veiculoModelo = veiculoModelo; }

    public String getVeiculoPlaca() { return veiculoPlaca; }
    public void setVeiculoPlaca(String veiculoPlaca) { this.veiculoPlaca = veiculoPlaca; }

    public Integer getVeiculoAno() { return veiculoAno; }
    public void setVeiculoAno(Integer veiculoAno) { this.veiculoAno = veiculoAno; }

    public String getVeiculoCor() { return veiculoCor; }
    public void setVeiculoCor(String veiculoCor) { this.veiculoCor = veiculoCor; }

    public String getNomeFantasia() { return nomeFantasia; }
    public void setNomeFantasia(String nomeFantasia) { this.nomeFantasia = nomeFantasia; }

    public String getEnderecoComercial() { return enderecoComercial; }
    public void setEnderecoComercial(String enderecoComercial) { this.enderecoComercial = enderecoComercial; }

    public int getTentativasLogin() { return tentativasLogin == null ? 0 : tentativasLogin; }
    public void setTentativasLogin(Integer tentativasLogin) { this.tentativasLogin = tentativasLogin; }

    public LocalDateTime getBloqueadoAte() { return bloqueadoAte; }
    public void setBloqueadoAte(LocalDateTime bloqueadoAte) { this.bloqueadoAte = bloqueadoAte; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
