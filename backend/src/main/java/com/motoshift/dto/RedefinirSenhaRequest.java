package com.motoshift.dto;

import com.motoshift.entity.Usuario;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Corpo de {@code POST /api/auth/redefinir-senha}: e-mail + código + senha nova. */
public class RedefinirSenhaRequest {

    @Email(message = "E-mail inválido")
    @NotBlank(message = "E-mail é obrigatório")
    private String email;

    /**
     * O formato é conferido aqui para que um código malformado não gaste uma
     * das cinco tentativas: "12345" é erro de digitação, não palpite.
     */
    @NotBlank(message = "Informe o código")
    @Pattern(regexp = "\\d{6}", message = "O código tem 6 dígitos")
    private String codigo;

    @NotBlank(message = "Informe a senha nova")
    @Size(min = 6, message = "A senha deve ter no mínimo 6 caracteres")
    private String senhaNova;

    public String getEmail() { return email; }

    /** Normalizado na entrada, antes da validação — ver LoginRequest.setEmail. */
    public void setEmail(String email) { this.email = Usuario.normalizarEmail(email); }

    public String getCodigo() { return codigo; }

    /** Sem os espaços que o copiar-e-colar do e-mail costuma trazer. */
    public void setCodigo(String codigo) { this.codigo = codigo == null ? null : codigo.trim(); }

    public String getSenhaNova() { return senhaNova; }
    public void setSenhaNova(String senhaNova) { this.senhaNova = senhaNova; }
}
