package com.motoshift.repository;

import com.motoshift.entity.Usuario;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Optional;

public interface UsuarioRepository extends JpaRepository<Usuario, Long> {
    Optional<Usuario> findByEmail(String email);
    boolean existsByEmail(String email);

    // ── RF01: tentativas de login ─────────────────────────────────────────
    //
    // UPDATE direto, e não "carrega, soma um, salva": duas senhas erradas ao
    // mesmo tempo somam as duas, e o save da entidade inteira nao entra na
    // disputa com uma edicao de perfil. Cada metodo tem a propria transacao
    // porque o login falho termina lancando excecao — se o incremento vivesse
    // na transacao do login, o rollback apagaria justamente a tentativa que
    // precisa ficar registrada.

    @Transactional
    @Modifying
    @Query("update Usuario u set u.tentativasLogin = u.tentativasLogin + 1 where u.id = :id")
    int registrarFalhaDeLogin(@Param("id") Long id);

    @Transactional
    @Modifying
    @Query("update Usuario u set u.tentativasLogin = 0, u.bloqueadoAte = :ate where u.id = :id")
    int bloquearLogin(@Param("id") Long id, @Param("ate") LocalDateTime ate);

    @Transactional
    @Modifying
    @Query("update Usuario u set u.tentativasLogin = 0, u.bloqueadoAte = null where u.id = :id")
    int liberarLogin(@Param("id") Long id);
}
