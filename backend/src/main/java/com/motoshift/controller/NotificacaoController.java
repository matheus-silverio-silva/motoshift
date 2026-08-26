package com.motoshift.controller;

import com.motoshift.entity.Notificacao;
import com.motoshift.service.NotificacaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/notificacoes")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Notificacoes", description = "Notificacoes in-app do usuario (RF09 / SCRUM-20)")
public class NotificacaoController {

    private final NotificacaoService service;

    public NotificacaoController(NotificacaoService service) {
        this.service = service;
    }

    @Operation(summary = "Listar notificacoes do usuario")
    @GetMapping
    public List<Map<String, Object>> listar(
            @RequestParam Long usuarioId,
            @RequestParam(required = false, value = "apenasNaoLidas") Boolean apenasNaoLidas) {
        boolean somenteNaoLidas = apenasNaoLidas != null && apenasNaoLidas;
        return service.listar(usuarioId, somenteNaoLidas).stream()
                .map(this::toMap)
                .collect(Collectors.toList());
    }

    @Operation(summary = "Contagem de nao lidas (badge do sino)")
    @GetMapping("/contagem")
    public Map<String, Object> contagem(@RequestParam Long usuarioId) {
        return Map.of("naoLidas", service.contarNaoLidas(usuarioId));
    }

    @Operation(summary = "Marcar uma notificacao como lida")
    @PutMapping("/{id}/lida")
    public Map<String, Object> marcarLida(@PathVariable Long id) {
        service.marcarComoLida(id);
        return Map.of("ok", true);
    }

    @Operation(summary = "Marcar todas como lidas")
    @PutMapping("/marcar-todas-lidas")
    public Map<String, Object> marcarTodas(@RequestParam Long usuarioId) {
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
