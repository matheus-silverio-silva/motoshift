package com.motoshift.dto;

public class AuthResponse {

    private String token;
    private UsuarioResponse usuario;

    public AuthResponse(String token, UsuarioResponse usuario) {
        this.token = token;
        this.usuario = usuario;
    }

    public String getToken() { return token; }
    public UsuarioResponse getUsuario() { return usuario; }
}
