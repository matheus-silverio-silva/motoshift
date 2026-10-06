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

    // Ignorado na autenticação, mas aceito para não quebrar o JSON do Flutter
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
