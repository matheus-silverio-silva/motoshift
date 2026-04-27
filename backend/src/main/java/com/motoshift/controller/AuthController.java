package com.motoshift.controller;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.LoginRequest;
import com.motoshift.dto.RegistroRequest;
import com.motoshift.dto.UsuarioResponse;
import com.motoshift.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Autenticação", description = "Registro e login de usuários (RF01, RF03)")
public class AuthController {

    private final AuthService service;

    public AuthController(AuthService service) {
        this.service = service;
    }

    @Operation(summary = "Registrar novo usuário",
               description = "Cria conta de Lojista (exige CNPJ) ou Motoboy (exige CNH).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Usuário criado — retorna token e dados"),
        @ApiResponse(responseCode = "400", description = "Dados inválidos ou documento ausente"),
        @ApiResponse(responseCode = "409", description = "E-mail já cadastrado")
    })
    @PostMapping("/registro")
    public ResponseEntity<AuthResponse> registro(@Valid @RequestBody RegistroRequest req) {
        return ResponseEntity.ok(service.registrar(req));
    }

    @Operation(summary = "Login",
               description = "Autentica usuário. Bloqueia por 15 min após 5 tentativas falhas (RF01).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Login bem-sucedido — retorna token JWT e perfil"),
        @ApiResponse(responseCode = "401", description = "Credenciais inválidas"),
        @ApiResponse(responseCode = "429", description = "Conta bloqueada por excesso de tentativas")
    })
    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest req) {
        return ResponseEntity.ok(service.login(req));
    }
}
