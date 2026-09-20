package com.motoshift.repository;

import com.motoshift.entity.Notificacao;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface NotificacaoRepository extends JpaRepository<Notificacao, Long> {

    List<Notificacao> findTop50ByUsuarioIdOrderByCriadoEmDesc(Long usuarioId);

    List<Notificacao> findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(Long usuarioId);

    // Versões paginadas das duas listagens do sino. Sem página, o serviço pede
    // a primeira de 50 — o mesmo teto do findTop50 acima.
    Page<Notificacao> findByUsuarioIdOrderByCriadoEmDesc(Long usuarioId, Pageable pagina);

    Page<Notificacao> findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(Long usuarioId, Pageable pagina);

    long countByUsuarioIdAndLidaFalse(Long usuarioId);

    // Deduplicação: evita que um job agendado repita a mesma notificação.
    boolean existsByUsuarioIdAndTipoAndReferenciaId(
            Long usuarioId, String tipo, Long referenciaId);

    // Limpeza periódica do histórico.
    List<Notificacao> findByLidaTrueAndCriadoEmBefore(LocalDateTime limite);
}
