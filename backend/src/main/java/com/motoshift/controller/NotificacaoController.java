package com.motoshift.controller;

import com.motoshift.entity.Notificacao;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.NotificacaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/notificacoes")
@Tag(name = "Notificacoes", description = "Notificacoes in-app do usuario (RF09 / SCRUM-20)")
public class NotificacaoController {

    private final NotificacaoService service;

    public NotificacaoController(NotificacaoService service) {
        this.service = service;
    }

    @Operation(summary = "Listar notificacoes do usuario",
            description = "Da mais recente para a mais antiga. Sem pagina, devolve as 50 "
                        + "mais recentes; o total vai no header X-Total-Count.")
    @GetMapping
    public ResponseEntity<List<Map<String, Object>>> listar(
            @RequestParam Long usuarioId,
            @RequestParam(required = false, value = "apenasNaoLidas") Boolean apenasNaoLidas,
            @RequestParam(required = false) Integer pagina,
            @RequestParam(required = false) Integer tamanho,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        boolean somenteNaoLidas = apenasNaoLidas != null && apenasNaoLidas;
        return Paginacao.resposta(
                service.listar(usuarioId, somenteNaoLidas, Paginacao.pedido(pagina, tamanho))
                        .map(this::toMap));
    }

    @Operation(summary = "Contagem de nao lidas (badge do sino)")
    @GetMapping("/contagem")
    public Map<String, Object> contagem(@RequestParam Long usuarioId,
                                        @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return Map.of("naoLidas", service.contarNaoLidas(usuarioId));
    }

    @Operation(summary = "Marcar uma notificacao como lida")
    @PutMapping("/{id}/lida")
    public Map<String, Object> marcarLida(@PathVariable Long id,
                                          @AuthenticationPrincipal UsuarioAutenticado atual) {
        // A notificacao e identificada so pelo id; sem o dono junto, qualquer
        // um marcaria a caixa de entrada alheia como lida.
        service.marcarComoLida(id, atual.id());
        return Map.of("ok", true);
    }

    @Operation(summary = "Marcar todas como lidas")
    @PutMapping("/marcar-todas-lidas")
    public Map<String, Object> marcarTodas(@RequestParam Long usuarioId,
                                           @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return Map.of("atualizadas", service.marcarTodasComoLidas(usuarioId));
    }

    private Map<String, Object> toMap(Notificacao n) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", n.getId());
        m.put("tipo", n.getTipo());
        m.put("titulo", n.getTitulo());
        m.put("mensagem", n.getMensagem());
        m.put("referenciaTipo", n.getReferenciaTipo());
        m.put("referenciaId", n.getReferenciaId());
        m.put("lida", n.getLida());
        m.put("criadoEm", n.getCriadoEm());
        return m;
    }
}
