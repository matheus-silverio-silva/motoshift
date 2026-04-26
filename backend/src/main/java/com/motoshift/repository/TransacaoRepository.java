package com.motoshift.repository;

import com.motoshift.entity.Transacao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TransacaoRepository extends JpaRepository<Transacao, Long> {

    List<Transacao> findByMotoboyIdOrderByCriadoEmDesc(Long motoboyId);
}
