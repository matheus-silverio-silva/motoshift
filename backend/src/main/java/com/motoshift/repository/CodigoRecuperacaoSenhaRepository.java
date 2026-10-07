package com.motoshift.repository;

import com.motoshift.entity.CodigoRecuperacaoSenha;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

public interface CodigoRecuperacaoSenhaRepository extends JpaRepository<CodigoRecuperacaoSenha, Long> {

    /** O código que vale: o mais recente da conta. Os anteriores já foram apagados. */
    Optional<CodigoRecuperacaoSenha> findFirstByUsuarioIdOrderByIdDesc(Long usuarioId);

    /**
     * Gasta uma das tentativas do código — e diz se ainda havia alguma.
     *
     * <p>UPDATE condicional, e não "lê, confere o limite, soma um": com a
     * condição dentro do UPDATE, dez palpites simultâneos gastam no máximo
     * {@code limite} tentativas, porque o banco serializa as linhas. Lendo
     * antes, os dez veriam "0 tentativas" e os dez seriam conferidos.
     *
     * <p>Transação própria pelo mesmo motivo do contador de login
     * ({@code UsuarioRepository.registrarFalhaDeLogin}): o palpite errado
     * termina em exceção, e a tentativa gasta precisa ficar gravada.
     *
     * @return 1 se a tentativa foi gasta; 0 se o código já estava esgotado
     */
    @Transactional
    @Modifying
    @Query("update CodigoRecuperacaoSenha c set c.tentativas = c.tentativas + 1 "
         + "where c.id = :id and c.tentativas < :limite")
    int gastarTentativa(@Param("id") Long id, @Param("limite") int limite);

    @Transactional
    @Modifying
    @Query("delete from CodigoRecuperacaoSenha c where c.usuarioId = :usuarioId")
    int apagarDoUsuario(@Param("usuarioId") Long usuarioId);
}
