package com.motoshift.controller;

import com.motoshift.dto.NotaFiscalPendenteResponse;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.NotaFiscalService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Nota fiscal de serviço dos turnos.
 *
 * Nenhuma rota recebe o id do usuário: quem pergunta sai do token, e é ele que
 * define o que a resposta traz — as notas em que a pessoa é prestadora ou
 * tomadora, e nada além disso.
 */
@RestController
@RequestMapping("/api/notas-fiscais")
@Tag(name = "Notas fiscais", description = "Emissão e consulta de NFS-e dos turnos concluídos")
public class NotaFiscalController {

    private final NotaFiscalService service;

    public NotaFiscalController(NotaFiscalService service) {
        this.service = service;
    }

    @Operation(summary = "Minhas notas fiscais",
            description = "Notas em que o usuário é prestador (entregador) ou tomador (lojista).")
    @ApiResponse(responseCode = "200", description = "Lista de notas")
    @GetMapping
    public List<NotaFiscalResponse> listar(@AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.listarDoUsuario(atual.id());
    }

    @Operation(summary = "Turnos a emitir",
            description = "Turnos finalizados que ainda não geraram nota. "
                    + "O lojista recebe um item por entregador do turno.")
    @ApiResponse(responseCode = "200", description = "Pendências de emissão")
    @GetMapping("/pendentes")
    public List<NotaFiscalPendenteResponse> pendentes(
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.pendentes(atual.id(), atual.isLojista());
    }

    @Operation(summary = "Emitir nota fiscal",
            description = "Emite a NFS-e do turno. Os dois lados podem emitir: o documento é "
                    + "sempre o mesmo, com o entregador como prestador e o lojista como tomador. "
                    + "Idempotente — pedir de novo devolve a nota já emitida, com 200.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Nota emitida"),
        @ApiResponse(responseCode = "200", description = "Nota já existia; devolvida como está"),
        @ApiResponse(responseCode = "403", description = "Usuário não participou do turno"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno ainda não finalizado")
    })
    @PostMapping
    public ResponseEntity<NotaFiscalResponse> emitir(
            @RequestBody Map<String, Object> body,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        Long turnoId = numero(body.get("turnoId"));
        if (turnoId == null) {
            return ResponseEntity.badRequest().build();
        }
        NotaFiscalService.Emissao r =
                service.emitir(turnoId, numero(body.get("prestadorId")), atual.id());
        return ResponseEntity
                .status(r.criada() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(r.nota());
    }

    @Operation(summary = "Consultar nota fiscal")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Nota encontrada"),
        @ApiResponse(responseCode = "403", description = "A nota não é do usuário"),
        @ApiResponse(responseCode = "404", description = "Nota não encontrada")
    })
    @GetMapping("/{id}")
    public NotaFiscalResponse buscar(@PathVariable Long id,
                                     @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.buscar(id, atual.id());
    }

    @Operation(summary = "Cancelar nota fiscal",
            description = "Só o prestador do serviço cancela a própria nota.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Nota cancelada"),
        @ApiResponse(responseCode = "403", description = "Apenas o prestador pode cancelar"),
        @ApiResponse(responseCode = "409", description = "Nota já cancelada")
    })
    @PutMapping("/{id}/cancelar")
    public NotaFiscalResponse cancelar(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body,
                                       @AuthenticationPrincipal UsuarioAutenticado atual) {
        String motivo = body == null ? null : body.get("motivo");
        return service.cancelar(id, motivo, atual.id());
    }

    /** O JSON pode trazer o id como Integer ou Long dependendo do cliente. */
    private Long numero(Object valor) {
        if (valor instanceof Number n) return n.longValue();
        if (valor instanceof String s && !s.isBlank()) {
            try {
                return Long.parseLong(s.trim());
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }
}
