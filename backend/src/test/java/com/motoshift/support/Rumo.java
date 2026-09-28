package com.motoshift.support;

/**
 * Ponto a uma distância e um rumo de outro, na mesma esfera do Haversine do
 * {@code GeoUtils} (raio médio de 6371,0088 km).
 *
 * <p>Fica nos testes, e não no {@code GeoUtils}, de propósito: é o jeito de
 * posicionar um turno "a exatamente 30 km ao norte" sem usar a própria conta
 * que o teste quer conferir.
 */
public final class Rumo {

    public static final double RAIO_TERRA_KM = 6371.0088;

    private Rumo() {}

    /**
     * @param rumoGraus 0 = norte, 90 = leste, 180 = sul, 270 = oeste
     * @return {latitude, longitude}
     */
    public static double[] destino(double lat, double lng, double rumoGraus, double distanciaKm) {
        double delta = distanciaKm / RAIO_TERRA_KM;
        double theta = Math.toRadians(rumoGraus);
        double phi1 = Math.toRadians(lat);
        double lambda1 = Math.toRadians(lng);

        double phi2 = Math.asin(Math.sin(phi1) * Math.cos(delta)
                + Math.cos(phi1) * Math.sin(delta) * Math.cos(theta));
        double lambda2 = lambda1 + Math.atan2(
                Math.sin(theta) * Math.sin(delta) * Math.cos(phi1),
                Math.cos(delta) - Math.sin(phi1) * Math.sin(phi2));
        return new double[] {Math.toDegrees(phi2), Math.toDegrees(lambda2)};
    }

    /**
     * O ponto de maior longitude de um círculo de raio [distanciaKm]: na
     * esfera ele não fica na latitude do centro, mas um pouco na direção do
     * polo. É o ponto que uma caixa estreita demais corta primeiro.
     */
    public static double[] extremoLeste(double lat, double lng, double distanciaKm) {
        double delta = distanciaKm / RAIO_TERRA_KM;
        double phi = Math.toRadians(lat);
        double latTangente = Math.toDegrees(Math.asin(Math.sin(phi) / Math.cos(delta)));
        double dLng = Math.toDegrees(Math.asin(Math.sin(delta) / Math.cos(phi)));
        return new double[] {latTangente, lng + dLng};
    }
}
