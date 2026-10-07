package com.motoshift.controller;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.EsqueciSenhaRequest;
import com.motoshift.dto.LoginRequest;
import com.motoshift.dto.RedefinirSenhaRequest;
import com.motoshift.dto.RegistroRequest;
import com.motoshift.dto.TrocarSenhaRequest;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.AuthService;
import com.motoshift.service.SenhaService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
@Tag(name = "Autenticação", description = "Registro, login e senha (RF01, RF03)")
public class AuthController {

    private final AuthService service;
    private final SenhaService senhas;

    public AuthController(AuthService service, SenhaService senhas) {
        this.service = service;
        this.senhas = senhas;
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

    // ── Senha (SCRUM-32) ──────────────────────────────────────────────────

    @Operation(summary = "Trocar a senha",
               description = "De quem está logado: exige a senha atual. A senha atual errada "
                       + "responde 400 e não conta como tentativa de login.")
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "Senha trocada"),
        @ApiResponse(responseCode = "400", description = "Senha atual não confere, ou senha nova com menos de 6 caracteres"),
        @ApiResponse(responseCode = "401", description = "Sem token")
    })
    @PostMapping("/trocar-senha")
    public ResponseEntity<Void> trocarSenha(@Valid @RequestBody TrocarSenhaRequest req,
                                            @AuthenticationPrincipal UsuarioAutenticado atual) {
        senhas.trocar(atual.id(), req.getSenhaAtual(), req.getSenhaNova());
        return ResponseEntity.noContent().build();
    }

    @Operation(summary = "Esqueci minha senha",
               description = "Gera um código de 6 dígitos, válido por 15 minutos, e o envia ao "
                       + "e-mail da conta (envio simulado: o código sai no log do servidor). "
                       + "Responde 202 exista ou não a conta.")
    @ApiResponses({
        @ApiResponse(responseCode = "202", description = "Pedido aceito — não diz se o e-mail tem conta"),
        @ApiResponse(responseCode = "400", description = "E-mail malformado")
    })
    @PostMapping("/esqueci-senha")
    public ResponseEntity<Map<String, String>> esqueciSenha(@Valid @RequestBody EsqueciSenhaRequest req) {
        senhas.pedirCodigo(req.getEmail());
        return ResponseEntity.accepted().body(Map.of("mensagem",
                "Se houver uma conta com este e-mail, enviamos um código de 6 dígitos para ele."));
    }

    @Operation(summary = "Redefinir a senha com o código",
               description = "E-mail + código + senha nova. Cada código aceita no máximo 5 tentativas.")
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "Senha redefinida — o login volta a aceitar a conta"),
        @ApiResponse(responseCode = "400", description = "Código inválido, vencido ou esgotado; ou dados malformados")
    })
    @PostMapping("/redefinir-senha")
    public ResponseEntity<Void> redefinirSenha(@Valid @RequestBody RedefinirSenhaRequest req) {
        senhas.redefinir(req.getEmail(), req.getCodigo(), req.getSenhaNova());
        return ResponseEntity.noContent().build();
    }
}
