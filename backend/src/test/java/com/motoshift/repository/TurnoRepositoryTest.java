package com.motoshift.repository;

import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * As tres consultas escritas a mao do TurnoRepository, contra um banco de
 * verdade.
 *
 * Nao havia nenhum {@code @DataJpaTest} no projeto. O contexto do Spring so
 * garante que a JPQL compila: se o BETWEEN da bounding box invertesse latitude
 * com longitude, ou se o OR da agenda esquecesse o lojista, tudo continuaria
 * subindo — e a lista sairia errada em producao, calada.
 *
 * Os ids sao altos de proposito para nao colidirem com a massa do
 * DataInitializer.
 */
@DataJpaTest
@ActiveProfiles("test")
class TurnoRepositoryTest {

    // Curitiba, mais ou menos no centro.
    private static final double LAT = -25.4284;
    private static final double LNG = -49.2733;

    @Autowired
    private TurnoRepository repo;

    @Test
    @DisplayName("findAbertosNaArea traz so o que esta dentro da caixa, e so o que esta aberto")
    void findAbertosNaArea_filtraPelaCaixaEPeloStatus() {
        Turno dentro = salvar("Dentro da area", StatusTurno.ABERTO, LAT + 0.01, LNG + 0.01);
        salvar("Fora da area", StatusTurno.ABERTO, LAT + 5.0, LNG + 5.0);
        salvar("Dentro mas ja aceito", StatusTurno.ACEITO, LAT + 0.01, LNG + 0.01);
        salvar("Dentro e sem coordenada", StatusTurno.ABERTO, null, null);

        List<Turno> achados = repo.findAbertosNaArea(
                LAT - 0.05, LAT + 0.05, LNG - 0.05, LNG + 0.05);

        assertThat(achados).extracting(Turno::getId).containsExactly(dentro.getId());
    }

    @Test
    @DisplayName("findByUsuarioAndPeriodo pega o usuario nos dois papeis, dentro da janela")
    void findByUsuarioAndPeriodo_lojistaEMotoboy() {
        LocalDateTime base = LocalDateTime.of(2026, 3, 10, 8, 0);

        Turno comoLojista = salvarComDatas("Publiquei", 900_001L, null, base.plusDays(1));
        Turno comoMotoboy = salvarComDatas("Aceitei", 900_002L, 900_001L, base.plusDays(2));
        salvarComDatas("De outra gente", 900_003L, 900_004L, base.plusDays(3));
        salvarComDatas("Fora da janela", 900_001L, null, base.plusDays(40));

        List<Turno> achados = repo.findByUsuarioAndPeriodo(
                900_001L, base, base.plusDays(30));

        assertThat(achados)
                .extracting(Turno::getId)
                .containsExactly(comoLojista.getId(), comoMotoboy.getId());
    }

    @Test
    @DisplayName("findByUsuarioAndPeriodo devolve em ordem cronologica")
    void findByUsuarioAndPeriodo_ordenado() {
        LocalDateTime base = LocalDateTime.of(2026, 5, 1, 8, 0);

        Turno tarde = salvarComDatas("Depois", 900_010L, null, base.plusDays(5));
        Turno cedo  = salvarComDatas("Antes",  900_010L, null, base.plusDays(1));

        List<Turno> achados = repo.findByUsuarioAndPeriodo(900_010L, base, base.plusDays(30));

        assertThat(achados)
                .extracting(Turno::getId)
                .containsExactly(cedo.getId(), tarde.getId());
    }

    @Test
    @DisplayName("findConflitos ignora turno aberto e pega o que se sobrepoe quando aceito")
    void findConflitos_soStatusAtivo() {
        LocalDateTime inicio = LocalDateTime.of(2026, 6, 1, 18, 0);
        LocalDateTime fim    = inicio.plusHours(4);

        Turno aceito = salvarComDatas("Sobrepoe e aceito", 900_020L, 900_021L, inicio.plusHours(1));
        aceito.setStatus(StatusTurno.ACEITO);
        repo.save(aceito);

        Turno aberto = salvarComDatas("Sobrepoe mas aberto", 900_020L, 900_021L, inicio.plusHours(2));
        aberto.setStatus(StatusTurno.ABERTO);
        repo.save(aberto);

        List<Turno> conflitos = repo.findConflitos(900_021L, inicio, fim);

        assertThat(conflitos).extracting(Turno::getId).containsExactly(aceito.getId());
    }

    // ── Helpers ──────────────────────────────────────────────

    private Turno salvar(String titulo, StatusTurno status, Double lat, Double lng) {
        Turno t = novo(titulo, 900_100L, null, LocalDateTime.of(2026, 4, 1, 10, 0));
        t.setStatus(status);
        t.setLatitude(lat);
        t.setLongitude(lng);
        return repo.save(t);
    }

    private Turno salvarComDatas(String titulo, Long lojistId, Long motoboyId, LocalDateTime inicio) {
        return repo.save(novo(titulo, lojistId, motoboyId, inicio));
    }

    private Turno novo(String titulo, Long lojistId, Long motoboyId, LocalDateTime inicio) {
        Turno t = new Turno();
        t.setTitulo(titulo);
        t.setLojistId(lojistId);
        t.setMotoboyId(motoboyId);
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        t.setValorEstimado(new BigDecimal("100.00"));
        return t;
    }
}
