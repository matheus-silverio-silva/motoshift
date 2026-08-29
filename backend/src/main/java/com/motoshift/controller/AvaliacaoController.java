package com.motoshift.controller;

import com.motoshift.dto.AvaliacaoRequest;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.AvaliacaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/avaliacoes")
@Tag(name = "Avaliações", description = "Avaliação mútua entre lojistas e motoboys")
public class AvaliacaoController {

    private final AvaliacaoService service;

    public AvaliacaoController(AvaliacaoService service) {
        this.service = service;
    }

    @Operation(summary = "Registrar avaliação",
               description = "O avaliador é sempre o dono do token; o corpo diz apenas "
                           + "quem está sendo avaliado e a nota.")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> avaliar(@Valid @RequestBody AvaliacaoRequest req,
                                       @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.avaliar(req, atual.id());
    }

    @Operation(summary = "Avaliações recebidas por um usuário")
    @GetMapping("/usuario/{usuarioId}")
    public Map<String, Object> avaliacoesDoUsuario(@PathVariable Long usuarioId) {
        // Reputação é visível entre usuários autenticados: o lojista precisa ver
        // as notas de quem se candidatou, e o entregador as da loja.
        return service.recebidasPor(usuarioId);
    }

    @Operation(summary = "IDs de turnos que o usuário já avaliou")
    @GetMapping("/feitas/{avaliadorId}")
    public Map<String, Object> turnosAvaliados(@PathVariable Long avaliadorId,
                                               @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(avaliadorId);
        return service.turnosAvaliadosPor(avaliadorId);
    }

    @Operation(summary = "Quem o usuário ainda precisa avaliar neste turno",
            description = "Em turno multi-vaga o lojista avalia cada entregador. "
                    + "Mantém 'precisaAvaliar' por compatibilidade e acrescenta a lista 'pendentes'.")
    @GetMapping("/turno/{turnoId}/pendentes/{usuarioId}")
    public Map<String, Object> pendente(@PathVariable Long turnoId,
                                        @PathVariable Long usuarioId,
                                        @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return service.pendentesNoTurno(turnoId, usuarioId);
    }
}
