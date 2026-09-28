package com.motoshift.controller;

import com.motoshift.dto.FavoritoResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.FavoritoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/favoritos")
@Tag(name = "Favoritos", description = "Os entregadores favoritos da loja")
public class FavoritoController {

    private final FavoritoService favoritos;

    public FavoritoController(FavoritoService favoritos) {
        this.favoritos = favoritos;
    }

    @Operation(summary = "Meus entregadores favoritos", description = "Só o lojista; do mais recente ao mais antigo.")
    @ApiResponse(responseCode = "200", description = "Lista de favoritos")
    @GetMapping
    public List<FavoritoResponse> listar(@AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("lojista");
        return favoritos.listar(atual.id());
    }

    @Operation(summary = "Favoritar entregador",
            description = "Só o lojista, só entregador. Favoritar de novo devolve o favorito que existe.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Favorito (novo ou já existente)"),
        @ApiResponse(responseCode = "403", description = "Quem pediu não é lojista"),
        @ApiResponse(responseCode = "404", description = "Entregador não encontrado"),
        @ApiResponse(responseCode = "422", description = "A conta não é de entregador")
    })
    @PutMapping("/{motoboyId}")
    public FavoritoResponse favoritar(@PathVariable Long motoboyId,
                                      @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("lojista");
        try {
            return favoritos.favoritar(atual.id(), motoboyId);
        } catch (DataIntegrityViolationException corrida) {
            // Dois cliques ao mesmo tempo: o outro gravou primeiro, e a chave
            // primária barrou este. Refeito, ele encontra o favorito que existe.
            return favoritos.favoritar(atual.id(), motoboyId);
        }
    }

    @Operation(summary = "Desfavoritar entregador", description = "Só o lojista. Sem favorito, não faz nada.")
    @ApiResponse(responseCode = "204", description = "Não é mais favorito")
    @DeleteMapping("/{motoboyId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void desfavoritar(@PathVariable Long motoboyId,
                             @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("lojista");
        favoritos.desfavoritar(atual.id(), motoboyId);
    }
}
