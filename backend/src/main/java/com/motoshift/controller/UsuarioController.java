package com.motoshift.controller;

import com.motoshift.dto.UsuarioResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/usuarios")
@Tag(name = "Usuários", description = "Consulta e atualização de perfis")
public class UsuarioController {

    private final AuthService service;

    public UsuarioController(AuthService service) {
        this.service = service;
    }

    @Operation(summary = "Buscar usuário por ID")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Perfil do usuário"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/{id}")
    public ResponseEntity<UsuarioResponse> buscar(@PathVariable Long id) {
        return ResponseEntity.ok(service.buscarPorId(id));
    }

    @Operation(summary = "Atualizar dados do usuário")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Perfil atualizado"),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @PutMapping("/{id}")
    public ResponseEntity<UsuarioResponse> atualizar(
            @PathVariable Long id,
            @RequestBody Map<String, Object> body,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        // Perfil alheio se le (o lojista precisa ver quem aceitou o turno),
        // mas so o dono edita.
        atual.exigirMesmoUsuario(id);
        return ResponseEntity.ok(service.atualizar(id, body));
    }
}
