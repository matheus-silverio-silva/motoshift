package com.motoshift.service;

import com.motoshift.entity.Notificacao;
import com.motoshift.repository.NotificacaoRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Criação e leitura de notificações in-app (SCRUM-20).
 *
 * Ponto único de entrada: nenhum outro service deve instanciar Notificacao
 * diretamente, para que a deduplicação valha para todo mundo.
 */
@Service
public class NotificacaoService {

    private final NotificacaoRepository repo;

    public NotificacaoService(NotificacaoRepository repo) {
        this.repo = repo;
    }

    /** Cria sempre — para eventos disparados por ação do usuário. */
    @Transactional
    public Notificacao criar(Long usuarioId, String tipo, String titulo,
                             String mensagem, String referenciaTipo, Long referenciaId) {
        if (usuarioId == null) return null;
        Notificacao n = new Notificacao();
        n.setUsuarioId(usuarioId);
        n.setTipo(tipo);
        n.setTitulo(titulo);
        n.setMensagem(truncar(mensagem, 255));
        n.setReferenciaTipo(referenciaTipo);
        n.setReferenciaId(referenciaId);
        return repo.save(n);
    }

    /**
     * Cria só se ainda não existir uma notificação do mesmo tipo para a mesma
     * referência. É esta a versão que os jobs agendados devem usar — sem ela,
     * um job de 5 em 5 minutos gera 12 notificações por hora do mesmo evento.
     */
    @Transactional
    public Notificacao criarUnica(Long usuarioId, String tipo, String titulo,
                                  String mensagem, String referenciaTipo, Long referenciaId) {
        if (usuarioId == null) return null;
        if (referenciaId != null
                && repo.existsByUsuarioIdAndTipoAndReferenciaId(usuarioId, tipo, referenciaId)) {
            return null;
        }
        return criar(usuarioId, tipo, titulo, mensagem, referenciaTipo, referenciaId);
    }

    public List<Notificacao> listar(Long usuarioId, boolean apenasNaoLidas) {
        return apenasNaoLidas
                ? repo.findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(usuarioId)
                : repo.findTop50ByUsuarioIdOrderByCriadoEmDesc(usuarioId);
    }

    public long contarNaoLidas(Long usuarioId) {
        return repo.countByUsuarioIdAndLidaFalse(usuarioId);
    }

    @Transactional
    public void marcarComoLida(Long id) {
        repo.findById(id).ifPresent(n -> {
            if (!n.getLida()) {
                n.setLida(true);
                n.setLidaEm(LocalDateTime.now());
                repo.save(n);
            }
        });
    }

    @Transactional
    public int marcarTodasComoLidas(Long usuarioId) {
        List<Notificacao> naoLidas = repo.findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(usuarioId);
        LocalDateTime agora = LocalDateTime.now();
        for (Notificacao n : naoLidas) {
            n.setLida(true);
            n.setLidaEm(agora);
            repo.save(n);
        }
        return naoLidas.size();
    }

    private String truncar(String s, int max) {
        if (s == null) return "";
        return s.length() <= max ? s : s.substring(0, max);
    }
}
