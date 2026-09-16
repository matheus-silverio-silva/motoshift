package com.motoshift.repository;

import com.motoshift.entity.NotaFiscal;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface NotaFiscalRepository extends JpaRepository<NotaFiscal, Long> {

    Optional<NotaFiscal> findByTurnoIdAndPrestadorId(Long turnoId, Long prestadorId);

    List<NotaFiscal> findByTurnoId(Long turnoId);

    /**
     * Notas em que o usuário aparece — como prestador (entregador) ou como
     * tomador (lojista). É a lista da tela "Notas fiscais", que é a mesma para
     * os dois papéis: muda o lado em que a pessoa está no documento, não o
     * documento.
     */
    @Query("""
            select n from NotaFiscal n
            where n.prestadorId = :usuarioId or n.tomadorId = :usuarioId
            order by n.emitidaEm desc
            """)
    List<NotaFiscal> findDoUsuario(@Param("usuarioId") Long usuarioId);

    /** Maior número já emitido por um prestador — base do próximo sequencial. */
    @Query("select max(n.numero) from NotaFiscal n where n.prestadorId = :prestadorId")
    Integer ultimoNumeroDoPrestador(@Param("prestadorId") Long prestadorId);
}
