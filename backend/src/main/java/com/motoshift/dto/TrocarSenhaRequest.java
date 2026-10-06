package com.motoshift.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Corpo de {@code POST /api/auth/trocar-senha}. De quem é a conta, diz o token. */
public class TrocarSenhaRequest {

    @NotBlank(message = "Informe a senha atual")
    private String senhaAtual;

    @NotBlank(message = "Informe a senha nova")
    @Size(min = 6, message = "A senha deve ter no mínimo 6 caracteres")
    private String senhaNova;

    public String getSenhaAtual() { return senhaAtual; }
    public void setSenhaAtual(String senhaAtual) { this.senhaAtual = senhaAtual; }

    public String getSenhaNova() { return senhaNova; }
    public void setSenhaNova(String senhaNova) { this.senhaNova = senhaNova; }
}
