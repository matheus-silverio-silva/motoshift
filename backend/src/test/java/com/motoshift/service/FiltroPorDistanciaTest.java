package com.motoshift.service;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.support.Rumo;
import com.motoshift.util.GeoUtils;
import org.junit.jupiter.api.BeforeEach;
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
 * "Perto de mim" de ponta a ponta no banco: a caixa da consulta
 * ({@code findAbertosNaArea}), o refino pelo Haversine e a distância que volta
 * na resposta.
 *
 * <p>Os turnos são posicionados a uma distância exata do entregador com
 * {@link Rumo}, e não "um pouco para dentro": é na borda que a caixa e o
 * círculo discordavam.
 */
@DataJpaTest
@ActiveProfiles("test")
class FiltroPorDistanciaTest {

    // O entregador, no marco zero de Curitiba.
    private static final double LAT = -25.4284;
    private static final double LNG = -49.2733;

    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    private TurnoConsultaService consultas;

    @BeforeEach
    void montar() {
        consultas = new TurnoConsultaService(turnoRepo, inscricaoRepo, usuarioRepo,
                new TurnoMapper(inscricaoRepo), new TurnoAcesso(turnoRepo, inscricaoRepo));
    }

    @Test
    @DisplayName("raio de 1 km: 900 m entra, 1,1 km não")
    void raioDeUmKm() {
        Turno perto = aDistancia("900 m", 0, 0.9);
        aDistancia("1,1 km", 0, 1.1);

        assertThat(ids(buscar(1.0))).containsExactly(perto.getId());
    }

    @Test
    @DisplayName("raio de 30 km: 29,9 km entra, 30,1 km não")
    void raioDeTrintaKm() {
        Turno dentro = aDistancia("29,9 km", 45, 29.9);
        aDistancia("30,1 km", 45, 30.1);

        assertThat(ids(buscar(30.0))).containsExactly(dentro.getId());
    }

    @Test
    @DisplayName("turno exatamente na borda do raio aparece — nos quatro rumos")
    void naBorda() {
        Turno norte = aDistancia("norte", 0, 30.0);
        Turno leste = aDistancia("leste", 90, 30.0);
        Turno sul = aDistancia("sul", 180, 30.0);
        Turno oeste = aDistancia("oeste", 270, 30.0);

        assertThat(ids(buscar(30.0)))
                .containsExactlyInAnyOrder(norte.getId(), leste.getId(), sul.getId(), oeste.getId());
    }

    @Test
    @DisplayName("o ponto mais a leste do círculo aparece — era o primeiro que a caixa cortava")
    void extremoLeste() {
        double[] p = Rumo.extremoLeste(LAT, LNG, 30.0);
        Turno t = salvar("extremo leste", p[0], p[1], 8.0);

        assertThat(ids(buscar(30.0))).containsExactly(t.getId());
    }

    @Test
    @DisplayName("turno sem coordenada sai do filtro por distância, mas continua na lista sem ele")
    void semCoordenada() {
        Turno comPonto = aDistancia("com ponto", 0, 2.0);
        Turno semPonto = salvar("sem ponto", null, null, 8.0);

        assertThat(ids(buscar(5.0))).containsExactly(comPonto.getId());
        assertThat(ids(consultas.listarDisponiveisComFiltros(
                null, null, null, null, null, null, null, null, null, null)))
                .contains(comPonto.getId(), semPonto.getId());
    }

    @Test
    @DisplayName("a distância da resposta é o Haversine arredondado, e só vem quando a busca tem posição")
    void distanciaNaResposta() {
        aDistancia("a 2,34 km", 0, 2.34);

        TurnoResponse comPosicao = buscar(5.0).get(0);
        assertThat(comPosicao.getDistanciaKm()).isEqualTo(2.3);

        TurnoResponse semPosicao = consultas.listarDisponiveisComFiltros(
                null, null, null, null, null, null, "dataInicio", null, null, null).get(0);
        assertThat(semPosicao.getDistanciaKm()).isNull();
    }

    @Test
    @DisplayName("raio de entrega do turno (raioMaxKm) e distância até o entregador (raioKm) são filtros diferentes")
    void doisRaios() {
        // Perto do entregador, mas o turno roda 15 km.
        Turno pertoAreaGrande = aDistancia("perto, área grande", 0, 2.0, 15.0);
        // Perto e com área pequena.
        Turno pertoAreaPequena = aDistancia("perto, área pequena", 90, 2.5, 5.0);
        // Longe, com área pequena.
        aDistancia("longe, área pequena", 180, 20.0, 5.0);

        List<TurnoResponse> soDistancia = consultas.listarDisponiveisComFiltros(
                null, null, null, null, null, null, null, LAT, LNG, 5.0);
        assertThat(ids(soDistancia))
                .containsExactlyInAnyOrder(pertoAreaGrande.getId(), pertoAreaPequena.getId());

        List<TurnoResponse> distanciaEArea = consultas.listarDisponiveisComFiltros(
                null, null, null, 8.0, null, null, null, LAT, LNG, 5.0);
        assertThat(ids(distanciaEArea)).containsExactly(pertoAreaPequena.getId());
    }

    @Test
    @DisplayName("ordenar por distância põe o mais perto primeiro")
    void ordenadoPorDistancia() {
        Turno longe = aDistancia("longe", 0, 7.0);
        Turno perto = aDistancia("perto", 180, 1.5);
        Turno meio = aDistancia("meio", 90, 4.0);

        List<TurnoResponse> r = consultas.listarDisponiveisComFiltros(
                null, null, null, null, null, null, "distanciaAsc", LAT, LNG, 10.0);
        assertThat(ids(r)).containsExactly(perto.getId(), meio.getId(), longe.getId());
    }

    // ── apoio ───────────────────────────────────────────────────────────────

    private List<TurnoResponse> buscar(double raioKm) {
        return consultas.listarDisponiveisComFiltros(
                null, null, null, null, null, null, "distanciaAsc", LAT, LNG, raioKm);
    }

    private Turno aDistancia(String titulo, double rumo, double km) {
        return aDistancia(titulo, rumo, km, 8.0);
    }

    private Turno aDistancia(String titulo, double rumo, double km, double raioEntrega) {
        double[] p = Rumo.destino(LAT, LNG, rumo, km);
        Turno t = salvar(titulo, p[0], p[1], raioEntrega);
        // Conferência do próprio teste: o ponto está mesmo onde diz estar.
        assertThat(GeoUtils.distanciaKm(LAT, LNG, t.getLatitude(), t.getLongitude()))
                .isCloseTo(km, org.assertj.core.api.Assertions.within(1e-6));
        return t;
    }

    private Turno salvar(String titulo, Double lat, Double lng, double raioEntrega) {
        Turno t = new Turno();
        t.setLojistId(910_001L);
        t.setTitulo(titulo);
        t.setRegiao("Curitiba");
        LocalDateTime inicio = LocalDateTime.now().plusDays(2);
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        t.setValorEstimado(new BigDecimal("100.00"));
        t.setRaioEntregaKm(raioEntrega);
        t.setLatitude(lat);
        t.setLongitude(lng);
        t.setStatus(StatusTurno.ABERTO);
        return turnoRepo.save(t);
    }

    private static List<Long> ids(List<TurnoResponse> r) {
        return r.stream().map(TurnoResponse::getId).toList();
    }
}
