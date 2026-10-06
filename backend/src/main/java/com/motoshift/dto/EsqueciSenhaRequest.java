package com.motoshift.dto;

import com.motoshift.entity.Usuario;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

/** Corpo de {@code POST /api/auth/esqueci-senha}. */
public class EsqueciSenhaRequest {

    @Email(message = "E-mail inválido")
    @NotBlank(message = "E-mail é obrigatório")
    private String email;

    public String getEmail() { return email; }

    /** Normalizado na entrada, antes da validação — ver LoginRequest.setEmail. */
    public void setEmail(String email) { this.email = Usuario.normalizarEmail(email); }
}
