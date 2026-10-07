package com.motoshift.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/**
 * Um pedido de recuperação de senha (V24).
 *
 * <p>Guarda o <b>hash</b> do código de 6 dígitos, nunca o código: quem lê o
 * banco não consegue trocar a senha de ninguém. O código em claro existe só
 * na memória da requisição que o gerou e no e-mail que o leva.
 *
 * <p>Não há setter de {@code tentativas}: o contador sobe por UPDATE direto
 * (ver {@code CodigoRecuperacaoSenhaRepository.gastarTentativa}), que é o que
 * mantém o limite de pé quando dois palpites chegam ao mesmo tempo.
 */
@Entity
@Table(name = "codigos_recuperacao_senha",
       indexes = @Index(name = "ix_codigo_recuperacao_usuario", columnList = "usuarioId, id"))
public class CodigoRecuperacaoSenha {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, updatable = false)
    private Long usuarioId;

    @Column(nullable = false, length = 100, updatable = false)
    private String codigoHash;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @Column(nullable = false)
    private LocalDateTime expiraEm;

    @Column(nullable = false)
    private int tentativas;

    protected CodigoRecuperacaoSenha() {}

    public CodigoRecuperacaoSenha(Long usuarioId, String codigoHash,
                                  LocalDateTime criadoEm, LocalDateTime expiraEm) {
        this.usuarioId = usuarioId;
        this.codigoHash = codigoHash;
        this.criadoEm = criadoEm;
        this.expiraEm = expiraEm;
    }

    public boolean expirou(LocalDateTime agora) {
        return !agora.isBefore(expiraEm);
    }

    public Long getId() { return id; }
    public Long getUsuarioId() { return usuarioId; }
    public String getCodigoHash() { return codigoHash; }
    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getExpiraEm() { return expiraEm; }
    public int getTentativas() { return tentativas; }
}
