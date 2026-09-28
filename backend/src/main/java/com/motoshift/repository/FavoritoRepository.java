package com.motoshift.repository;

import com.motoshift.entity.Favorito;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Set;

public interface FavoritoRepository extends JpaRepository<Favorito, Favorito.Chave> {

    boolean existsByLojistaIdAndMotoboyId(Long lojistaId, Long motoboyId);

    List<Favorito> findByLojistaIdOrderByCriadoEmDesc(Long lojistaId);

    List<Favorito> findByLojistaId(Long lojistaId);

    /** As lojas que favoritaram este entregador — o selo da lista de disponíveis. */
    @Query("select f.lojistaId from Favorito f where f.motoboyId = :motoboyId")
    Set<Long> lojasQueFavoritaram(@Param("motoboyId") Long motoboyId);
}
