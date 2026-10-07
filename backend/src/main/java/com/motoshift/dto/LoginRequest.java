package com.motoshift.dto;

import com.motoshift.entity.Usuario;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public class LoginRequest {

    @Email
    @NotBlank
    private String email;

    @NotBlank
    private String senha;

    /**
     * Aceito e <b>não usado</b>. O perfil de quem entra é o da conta — vem do
     * e-mail, não do que a tela mandar —, e por isso a escolha "Sou Lojista /
     * Sou Motoboy" saiu da tela de login (SCRUM-49): ela não tinha efeito. O
     * campo continua aqui só para o app antigo, que ainda o envia, não levar
     * um erro de JSON no login. No cadastro o {@code tipo} vale, e é
     * obrigatório.
     */
    private String tipo;

    public String getEmail() { return email; }

    /**
     * Normalizado já na entrada (trim + minúsculas), antes da validação: com um
     * espaço na ponta — o autocompletar do celular costuma deixar um — o
     * {@code @Email} recusava o login com 400 antes de o serviço ver o valor.
     */
    public void setEmail(String email) { this.email = Usuario.normalizarEmail(email); }

    public String getSenha() { return senha; }
    public void setSenha(String senha) { this.senha = senha; }

    public String getTipo() { return tipo; }
    public void setTipo(String tipo) { this.tipo = tipo; }
}
