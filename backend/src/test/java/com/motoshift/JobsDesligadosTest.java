package com.motoshift;

import com.motoshift.service.TurnoExpiracaoJobs;
import com.motoshift.service.TurnoExpiracaoService;
import com.motoshift.service.TurnoLembreteService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A réplica sem jobs sobe.
 *
 * <p>O cabeçalho dos jobs manda subir as réplicas extras com
 * {@code MOTOSHIFT_JOBS_HABILITADOS=false} — e fazer isso derrubava o boot: o
 * {@code TurnoExpiracaoService} inteiro era condicional aos jobs, e a massa de
 * demonstração depende dele (é ele que vence o turno sem entregador da
 * história). Nenhum teste subia o contexto com os jobs desligados.
 *
 * <p>Com um banco próprio, para o boot semear a massa de novo — é ela que
 * exercita a dependência.
 */
@SpringBootTest(properties = {
        "motoshift.jobs.habilitados=false",
        "spring.datasource.url=jdbc:h2:mem:jobs-desligados;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
@ActiveProfiles("test")
class JobsDesligadosTest {

    @Autowired private ApplicationContext contexto;
    @Autowired private JdbcTemplate jdbc;

    @Test
    @DisplayName("com os jobs desligados o contexto sobe: nada é agendado, mas a regra continua disponível")
    void sobeSemAgendar() {
        assertThat(contexto.getBeansOfType(TurnoExpiracaoJobs.class)).isEmpty();
        assertThat(contexto.getBeansOfType(TurnoLembreteService.class)).isEmpty();
        // O serviço fica: é ele que a massa usa, e ele não agenda nada sozinho.
        assertThat(contexto.getBeansOfType(TurnoExpiracaoService.class)).hasSize(1);
    }

    @Test
    @DisplayName("e a massa de demonstração é semeada inteira, com o turno que venceu sem entregador")
    void massaSemeada() {
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email LIKE '%@teste.com'", Integer.class))
                .isEqualTo(8);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM turnos WHERE status = 'expirado'", Integer.class))
                .isEqualTo(1);
    }
}
