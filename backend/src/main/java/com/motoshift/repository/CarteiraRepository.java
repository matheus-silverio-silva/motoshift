package com.motoshift.repository;

import com.motoshift.entity.Carteira;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface CarteiraRepository extends JpaRepository<Carteira, Long> {

    Optional<Carteira> findByUsuarioId(Long usuarioId);

    boolean existsByUsuarioId(Long usuarioId);

    /**
     * @deprecated use {@link #findByUsuarioId(Long)}. A V4 preencheu usuario_id
     * em todas as carteiras existentes, entao a busca por usuario cobre tambem
     * as antigas de entregador.
     */
    @Deprecated
    Optional<Carteira> findByMotoboyId(Long motoboyId);
}
