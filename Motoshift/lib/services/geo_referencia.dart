import 'package:latlong2/latlong.dart';

/// De onde o mapa parte quando ainda não se sabe a posição exata.
///
/// Não é geocodificação: é uma tabela curta de centros de cidade, usada só
/// como ponto inicial enquanto o GPS não responde ou foi negado. O ponto que
/// vale é o que o lojista confirma tocando o mapa — este aqui só evita abrir a
/// tela no lugar errado.
///
/// Antes disso existia uma constante `_centro = LatLng(-23.4273, -51.9375)`
/// (Maringá-PR) na tela de publicar turno, enquanto o turno era gravado com
/// `regiao: 'São Paulo'` e os dados de exemplo ficam em Curitiba. Três cidades
/// diferentes na mesma tela — daí a impressão de que "o mapa não está certo".
class GeoReferencia {
  GeoReferencia._();

  /// Fallback final: Praça Tiradentes, marco zero de Curitiba — a mesma cidade
  /// dos dados de exemplo do backend (`DataInitializer`).
  static const LatLng padrao = LatLng(-25.4284, -49.2733);

  static const Map<String, LatLng> _cidades = {
    'curitiba': LatLng(-25.4284, -49.2733),
    'sao paulo': LatLng(-23.5505, -46.6333),
    'rio de janeiro': LatLng(-22.9068, -43.1729),
    'belo horizonte': LatLng(-19.9167, -43.9345),
    'porto alegre': LatLng(-30.0346, -51.2177),
    'florianopolis': LatLng(-27.5954, -48.5480),
    'maringa': LatLng(-23.4273, -51.9375),
    'londrina': LatLng(-23.3045, -51.1696),
    'joinville': LatLng(-26.3044, -48.8456),
    'brasilia': LatLng(-15.7939, -47.8828),
    'salvador': LatLng(-12.9777, -38.5016),
    'recife': LatLng(-8.0476, -34.8770),
    'fortaleza': LatLng(-3.7319, -38.5267),
    'goiania': LatLng(-16.6869, -49.2648),
    'campinas': LatLng(-22.9099, -47.0626),
  };

  /// Centro aproximado da cidade, ou [padrao] quando ela não está na tabela.
  static LatLng daCidade(String? cidade) {
    final chave = _normalizar(cidade);
    if (chave.isEmpty) return padrao;
    return _cidades[chave] ?? padrao;
  }

  /// A cidade é conhecida? Serve para a tela dizer "aproximado" em vez de
  /// fingir precisão que não tem.
  static bool conhece(String? cidade) =>
      _cidades.containsKey(_normalizar(cidade));

  /// Minúsculas e sem acento — "São Paulo", "sao paulo" e "SÃO PAULO" batem
  /// na mesma chave.
  static String _normalizar(String? valor) {
    if (valor == null) return '';
    const acentos = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const limpos = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final buffer = StringBuffer();
    for (final ch in valor.trim().split('')) {
      final i = acentos.indexOf(ch);
      buffer.write(i >= 0 ? limpos[i] : ch);
    }
    return buffer.toString().toLowerCase();
  }
}
