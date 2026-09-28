package com.motoshift.util;

import com.motoshift.support.Rumo;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * A caixa do banco (bounding box) e o círculo do Haversine precisam concordar
 * na borda: o que o Haversine diz estar dentro do raio tem de estar dentro da
 * caixa — senão o turno some antes de o refino exato ter a chance de aceitá-lo.
 *
 * <p>Era o que acontecia. A caixa usava 111,32 km por grau, e o Haversine usa o
 * raio médio da Terra (6371 km, 111,19 km por grau). A caixa saía ~0,1% menor
 * que o círculo: num raio de 30 km, um turno a 29,98 km ao norte ficava de
 * fora. Na longitude a diferença era maior, porque o ponto mais a leste de um
 * círculo na esfera não está na mesma latitude do centro.
 */
class GeoUtilsTest {

    /** Marco zero de Curitiba — latitude e longitude negativas, como todo o Brasil. */
    private static final double LAT = -25.4284;
    private static final double LNG = -49.2733;

    @ParameterizedTest(name = "raio de {0} km: o ponto na borda norte está dentro da caixa")
    @ValueSource(doubles = {1.0, 8.0, 30.0})
    void bordaNorteDentroDaCaixa(double raio) {
        double[] p = Rumo.destino(LAT, LNG, 0, raio);

        assertThat(GeoUtils.distanciaKm(LAT, LNG, p[0], p[1])).isCloseTo(raio, within(1e-9));
        assertThat(p[0] - LAT).isLessThanOrEqualTo(GeoUtils.deltaLatitude(raio));
    }

    @ParameterizedTest(name = "raio de {0} km: o ponto mais a leste do círculo está dentro da caixa")
    @ValueSource(doubles = {1.0, 8.0, 30.0})
    void extremoLesteDentroDaCaixa(double raio) {
        double[] p = Rumo.extremoLeste(LAT, LNG, raio);

        assertThat(GeoUtils.distanciaKm(LAT, LNG, p[0], p[1])).isCloseTo(raio, within(1e-6));
        assertThat(p[1] - LNG).isLessThanOrEqualTo(GeoUtils.deltaLongitude(raio, LAT));
    }

    @Test
    @DisplayName("exatamente na borda conta como dentro; um metro além, não")
    void bordaExata() {
        assertThat(GeoUtils.dentroDoRaio(30.0, 30.0)).isTrue();
        // O Haversine devolve 29.999999999999996 ou 30.000000000000004 para o
        // mesmo ponto, conforme a ordem das contas: a borda não pode depender disso.
        assertThat(GeoUtils.dentroDoRaio(30.000000000000004, 30.0)).isTrue();
        assertThat(GeoUtils.dentroDoRaio(30.001, 30.0)).isFalse();
        assertThat(GeoUtils.dentroDoRaio(null, 30.0)).isFalse();
    }

    @Test
    @DisplayName("sem coordenada não há distância")
    void semCoordenada() {
        assertThat(GeoUtils.distanciaKm(LAT, LNG, null, LNG)).isNull();
        assertThat(GeoUtils.distanciaKm(null, null, LAT, LNG)).isNull();
    }

    @Test
    @DisplayName("coordenadas negativas: sul e oeste medem como norte e leste")
    void hemisferioSulEOeste() {
        for (double rumo : new double[] {0, 90, 180, 270}) {
            double[] p = Rumo.destino(LAT, LNG, rumo, 12.5);
            assertThat(GeoUtils.distanciaKm(LAT, LNG, p[0], p[1]))
                    .as("rumo %s", rumo)
                    .isCloseTo(12.5, within(1e-9));
        }
        double[] sul = Rumo.destino(LAT, LNG, 180, 12.5);
        double[] oeste = Rumo.destino(LAT, LNG, 270, 12.5);
        assertThat(sul[0]).isLessThan(LAT);
        assertThat(oeste[1]).isLessThan(LNG);
    }

    @Test
    @DisplayName("coordenada fora do planeta é recusada; o Brasil inteiro é aceito")
    void coordenadaValida() {
        assertThat(GeoUtils.coordenadaValida(LAT, LNG)).isTrue();
        assertThat(GeoUtils.coordenadaValida(-33.75, -73.99)).isTrue(); // extremo sudoeste
        assertThat(GeoUtils.coordenadaValida(-91.0, LNG)).isFalse();
        assertThat(GeoUtils.coordenadaValida(LAT, -181.0)).isFalse();
        assertThat(GeoUtils.coordenadaValida(null, LNG)).isFalse();
    }
}
