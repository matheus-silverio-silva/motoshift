package com.motoshift.repository;

import com.motoshift.entity.LancamentoGerencial;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface LancamentoGerencialRepository extends JpaRepository<LancamentoGerencial, Long> {

    /**
     * O lançamento, se for deste usuário. É a consulta de todo editar e
     * excluir: quem não é o dono recebe o mesmo "não encontrado" de um id que
     * não existe, e não fica sabendo que o lançamento existe.
     */
    Optional<LancamentoGerencial> findByIdAndUsuarioId(Long id, Long usuarioId);

    /**
     * Os lançamentos que PODEM ter efeito em [inicio, fim]: os avulsos com a
     * data dentro, e os recorrentes que já começaram e ainda não terminaram.
     *
     * <p>"Podem", porque a recorrência é mensal: uma conta que vence todo dia
     * 20 está em vigor na semana de 1 a 7, mas não acontece nela. Quem decide
     * se aconteceu é {@code service.Recorrencia}, em Java — o dia do mês
     * limitado ao tamanho do mês não se escreve do mesmo jeito no H2 do dev e
     * no PostgreSQL de produção, e a quantidade por usuário é pequena.
     */
    @Query("SELECT l FROM LancamentoGerencial l "
         + "WHERE l.usuarioId = :usuarioId "
         + "AND ((l.recorrente = false AND l.data >= :inicio AND l.data <= :fim) "
         + "  OR (l.recorrente = true AND l.data <= :fim "
         + "      AND (l.recorrenteAte IS NULL OR l.recorrenteAte >= :inicio))) "
         + "ORDER BY l.data DESC, l.id DESC")
    List<LancamentoGerencial> candidatosNoPeriodo(@Param("usuarioId") Long usuarioId,
                                                  @Param("inicio") LocalDate inicio,
                                                  @Param("fim") LocalDate fim);
}
