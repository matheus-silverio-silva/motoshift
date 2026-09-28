package com.motoshift.util;

/**
 * Cálculos geográficos usados pelo filtro de turnos por raio (SCRUM-18).
 *
 * Usa a fórmula de Haversine, que assume a Terra como esfera. O erro é da
 * ordem de 0,5% — irrelevante para raios urbanos de 1 a 50 km.
 *
 * <p><b>A caixa e o círculo usam a mesma Terra.</b> O filtro por raio roda em
 * dois passos: uma caixa no banco (bounding box, que usa índice) e o refino
 * exato pelo Haversine. A caixa só pode descartar o que o círculo também
 * descartaria. Ela usava 111,32 km por grau, enquanto o Haversine usa o raio
 * médio abaixo — 111,19 km por grau —, e saía ~0,1% menor que o círculo: num
 * raio de 30 km, um turno a 29,98 km ao norte sumia antes do refino. Agora as
 * duas contas partem de {@link #RAIO_TERRA_KM} ({@code GeoUtilsTest}).
 */
public final class GeoUtils {

    /** Raio médio da Terra em km (IUGG mean radius). O mesmo para caixa e círculo. */
    public static final double RAIO_TERRA_KM = 6371.0088;

    /**
     * Folga da borda, em km (1 mm). O Haversine devolve 29,999999999999996 ou
     * 30,000000000000004 para o mesmo ponto conforme a ordem das contas; "até
     * 30 km" não pode depender disso.
     */
    private static final double FOLGA_DA_BORDA_KM = 1e-6;

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

    /** A distância cabe no raio (borda inclusive)? Sem distância — coordenada ausente —, não. */
    public static boolean dentroDoRaio(Double distanciaKm, double raioKm) {
        return distanciaKm != null && distanciaKm <= raioKm + FOLGA_DA_BORDA_KM;
    }

    public static boolean coordenadaValida(Double lat, Double lng) {
        return lat != null && lng != null
                && lat >= -90.0 && lat <= 90.0
                && lng >= -180.0 && lng <= 180.0;
    }

    /**
     * Meia-altura (em graus de latitude) de uma bounding box que contém o
     * círculo de raio {@code raioKm}. Usado como pré-filtro no banco.
     *
     * <p>Exata ao longo do meridiano: o arco de {@code raioKm} na mesma esfera
     * do Haversine.
     */
    public static double deltaLatitude(double raioKm) {
        return Math.toDegrees((raioKm + FOLGA_DA_BORDA_KM) / RAIO_TERRA_KM);
    }

    /**
     * Meia-largura (em graus de longitude) da mesma bounding box. Depende da
     * latitude: perto dos polos, 1 grau de longitude vale menos km.
     *
     * <p>Não é {@code raio / (km_por_grau × cos φ)}: o ponto mais a leste de um
     * círculo na esfera fica um pouco na direção do polo, e a largura exata é
     * {@code asin(sin δ / cos φ)}. A conta plana cortava justamente esse ponto.
     */
    public static double deltaLongitude(double raioKm, double latitude) {
        double delta = (raioKm + FOLGA_DA_BORDA_KM) / RAIO_TERRA_KM;
        double cos = Math.cos(Math.toRadians(latitude));
        double seno = Math.sin(delta) / Math.max(cos, 1e-9);
        // Círculo que passa por cima do polo: qualquer longitude serve.
        if (seno >= 1.0) return 180.0;
        return Math.toDegrees(Math.asin(seno));
    }

    /** Arredonda para 1 casa decimal, preservando null. */
    public static Double arredondar1(Double v) {
        if (v == null) return null;
        return Math.round(v * 10.0) / 10.0;
    }
}
