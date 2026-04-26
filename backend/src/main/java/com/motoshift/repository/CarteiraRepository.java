package com.motoshift.repository;

import com.motoshift.entity.Carteira;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface CarteiraRepository extends JpaRepository<Carteira, Long> {

    Optional<Carteira> findByMotoboyId(Long motoboyId);
}
