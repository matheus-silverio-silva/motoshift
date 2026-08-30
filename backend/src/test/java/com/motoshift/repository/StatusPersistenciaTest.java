package com.motoshift.repository;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O que o banco realmente guarda na coluna de status.
 *
 * O {@link com.motoshift.entity.StatusConverterTest} prova a regra do
 * converter isolado; este prova que a regra chega ao banco — que o converter
 * está de fato aplicado (o {@code autoApply}), que ninguém deixou um
 * {@code @Enumerated} no caminho e que o Hibernate não mapeou o enum como
 * ordinal.
 *
 * Por isso a leitura é por query nativa: passar pelo repositório traria o valor
 * de volta pelo converter, e um esquema todo em MAIÚSCULO passaria despercebido.
 */
@DataJpaTest
@ActiveProfiles("test")
class StatusPersistenciaTest {

    @Autowired
    private TurnoRepository turnoRepo;

    @Autowired
    private TurnoInscricaoRepository inscricaoRepo;

    @Autowired
    private EntityManager em;

    @Test
    @DisplayName("turnos.status e turnos.pagamento_status guardam o valor minúsculo")
    void turno_gravaMinusculo() {
        Turno t = new Turno();
        t.setTitulo("Turno de teste");
        t.setLojistId(900_500L);
        t.setDataInicio(LocalDateTime.of(2026, 7, 1, 18, 0));
        t.setDataFim(LocalDateTime.of(2026, 7, 1, 22, 0));
        t.setValorEstimado(new BigDecimal("100.00"));
        t.setStatus(StatusTurno.EM_ANDAMENTO);
        t.setPagamentoStatus(StatusPagamento.PENDENTE);
        turnoRepo.saveAndFlush(t);
        em.clear();

        Object[] bruto = (Object[]) em.createNativeQuery(
                        "SELECT status, pagamento_status FROM turnos WHERE id = :id")
                .setParameter("id", t.getId())
                .getSingleResult();

        assertThat(bruto[0]).isEqualTo("em_andamento");
        assertThat(bruto[1]).isEqualTo("pendente");

        // E volta como a mesma constante.
        Turno relido = turnoRepo.findById(t.getId()).orElseThrow();
        assertThat(relido.getStatus()).isEqualTo(StatusTurno.EM_ANDAMENTO);
        assertThat(relido.getPagamentoStatus()).isEqualTo(StatusPagamento.PENDENTE);
    }

    @Test
    @DisplayName("turno_inscricoes.status e pagamento_status guardam o valor minúsculo")
    void inscricao_gravaMinusculo() {
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(900_501L);
        ins.setMotoboyId(900_502L);
        ins.setStatus(StatusInscricao.FINALIZADO);
        ins.setPagamentoStatus(StatusPagamento.PAGO);
        inscricaoRepo.saveAndFlush(ins);
        em.clear();

        Object[] bruto = (Object[]) em.createNativeQuery(
                        "SELECT status, pagamento_status FROM turno_inscricoes WHERE id = :id")
                .setParameter("id", ins.getId())
                .getSingleResult();

        assertThat(bruto[0]).isEqualTo("finalizado");
        assertThat(bruto[1]).isEqualTo("pago");
    }

    @Test
    @DisplayName("pagamento_status nulo continua nulo no banco, e não vira string")
    void pagamentoNulo_continuaNulo() {
        Turno t = new Turno();
        t.setTitulo("Ainda nao finalizado");
        t.setLojistId(900_503L);
        t.setDataInicio(LocalDateTime.of(2026, 7, 2, 18, 0));
        t.setDataFim(LocalDateTime.of(2026, 7, 2, 22, 0));
        t.setValorEstimado(new BigDecimal("100.00"));
        turnoRepo.saveAndFlush(t);
        em.clear();

        Object bruto = em.createNativeQuery(
                        "SELECT pagamento_status FROM turnos WHERE id = :id")
                .setParameter("id", t.getId())
                .getSingleResult();

        assertThat(bruto).isNull();
        assertThat(turnoRepo.findById(t.getId()).orElseThrow().getPagamentoStatus()).isNull();
    }

    @Test
    @DisplayName("o default do @PrePersist grava aberto, e não ABERTO")
    void defaultDoPrePersist_eMinusculo() {
        Turno t = new Turno();
        t.setTitulo("Recem publicado");
        t.setLojistId(900_504L);
        t.setDataInicio(LocalDateTime.of(2026, 7, 3, 18, 0));
        t.setDataFim(LocalDateTime.of(2026, 7, 3, 22, 0));
        t.setValorEstimado(new BigDecimal("100.00"));
        turnoRepo.saveAndFlush(t);
        em.clear();

        Object bruto = em.createNativeQuery("SELECT status FROM turnos WHERE id = :id")
                .setParameter("id", t.getId())
                .getSingleResult();

        assertThat(bruto).isEqualTo("aberto");
    }
}
