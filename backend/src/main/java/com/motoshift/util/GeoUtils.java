package com.motoshift.util;

/**
 * Cálculos geográficos usados pelo filtro de turnos por raio (SCRUM-18).
 *
 * Usa a fórmula de Haversine, que assume a Terra como esfera. O erro é da
 * ordem de 0,5% — irrelevante para raios urbanos de 1 a 50 km.
 */
public final class GeoUtils {

    /** Raio médio da Terra em km (IUGG mean radius). */
    private static final double RAIO_TERRA_KM = 6371.0088;

    /** Aproximação de 1 grau de latitude em km. Constante em qualquer latitude. */
    private static final double KM_POR_GRAU_LAT = 111.32;

    private GeoUtils() {}

    /**
     * Distância em km entre dois pontos. Devolve {@code null} se qualquer
     * coordenada estiver ausente — quem chama decide se isso exclui ou não o
     * registro (turnos legados não têm coordenada).
     */
    public static Double distanciaKm(Double lat1, Double lon1, Double lat2, Double lon2) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return null;

        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                 * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return RAIO_TERRA_KM * c;
    }

    public static boolean coordenadaValida(Double lat, Double lng) {
        return lat != null && lng != null
                && lat >= -90.0 && lat <= 90.0
                && lng >= -180.0 && lng <= 180.0;
    }

    /**
     * Meia-altura (em graus de latitude) de uma bounding box que contém o
     * círculo de raio {@code raioKm}. Usado como pré-filtro no banco.
     */
    public static double deltaLatitude(double raioKm) {
        return raioKm / KM_POR_GRAU_LAT;
    }

    /**
     * Meia-largura (em graus de longitude) da mesma bounding box. Depende da
     * latitude: perto dos polos, 1 grau de longitude vale menos km.
     */
    public static double deltaLongitude(double raioKm, double latitude) {
        double cos = Math.cos(Math.toRadians(latitude));
        if (cos < 0.01) cos = 0.01; // evita divisão por ~zero perto dos polos
        return raioKm / (KM_POR_GRAU_LAT * cos);
    }

    /** Arredonda para 1 casa decimal, preservando null. */
    public static Double arredondar1(Double v) {
        if (v == null) return null;
        return Math.round(v * 10.0) / 10.0;
    }
}
