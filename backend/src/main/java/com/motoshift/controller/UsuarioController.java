package com.motoshift.controller;

import com.motoshift.dto.PerfilPublicoResponse;
import com.motoshift.dto.UsuarioResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
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

    @Operation(summary = "Buscar usuário por ID",
               description = "O próprio usuário recebe o perfil completo. Qualquer outra "
                           + "conta recebe só o perfil público — sem documento, CNH, "
                           + "nascimento, e-mail, telefone ou endereço.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Perfil completo ou público",
                content = @Content(schema = @Schema(
                        oneOf = {UsuarioResponse.class, PerfilPublicoResponse.class}))),
        @ApiResponse(responseCode = "404", description = "Usuário não encontrado")
    })
    @GetMapping("/{id}")
    public ResponseEntity<?> buscar(@PathVariable Long id,
                                    @AuthenticationPrincipal UsuarioAutenticado atual) {
        // Perfil alheio se lê (o lojista precisa ver quem aceitou o turno),
        // mas só na versão reduzida. O completo é dado pessoal do dono.
        if (id.equals(atual.id())) {
            return ResponseEntity.ok(service.buscarPorId(id));
        }
        return ResponseEntity.ok(service.buscarPerfilPublico(id));
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
        // Só o dono edita.
        atual.exigirMesmoUsuario(id);
        return ResponseEntity.ok(service.atualizar(id, body));
    }
}
