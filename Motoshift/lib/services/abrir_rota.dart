import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Os apps de navegação que o "Abrir rota" oferece.
enum AppDeRota { googleMaps, waze }

/// Quem abre um endereço fora do app. Trocável nos testes: o `url_launcher`
/// passa por canal de plataforma, que num teste não existe.
abstract class Navegador {
  Future<bool> abrir(Uri uri);
  Future<bool> consegueAbrir(Uri uri);
  bool get ehWeb;
}

class NavegadorDoSistema implements Navegador {
  const NavegadorDoSistema();

  @override
  Future<bool> abrir(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<bool> consegueAbrir(Uri uri) => canLaunchUrl(uri);

  @override
  bool get ehWeb => kIsWeb;
}

/// "Abrir rota" até o ponto do turno: Google Maps sempre; Waze quando está
/// instalado no celular.
///
/// No navegador não dá para saber que apps a pessoa tem — o Google Maps abre
/// numa aba nova, que é o que funciona em qualquer lugar. No celular, o
/// `waze://` só responde se o Waze estiver instalado (AndroidManifest e
/// Info.plist declaram a consulta), e só então ele aparece como opção.
class AbrirRota {
  AbrirRota({Navegador? navegador})
      : navegador = navegador ?? const NavegadorDoSistema();

  final Navegador navegador;

  static Uri googleMaps(double lat, double lng) => Uri.https(
        'www.google.com',
        '/maps/dir/',
        {'api': '1', 'destination': '$lat,$lng', 'travelmode': 'driving'},
      );

  static Uri waze(double lat, double lng) => Uri.https(
        'waze.com',
        '/ul',
        {'ll': '$lat,$lng', 'navigate': 'yes'},
      );

  static final Uri _wazeInstalado = Uri.parse('waze://');

  /// Os apps que fazem sentido oferecer neste aparelho, Google Maps primeiro.
  Future<List<AppDeRota>> disponiveis() async {
    if (navegador.ehWeb) return const [AppDeRota.googleMaps];
    try {
      if (await navegador.consegueAbrir(_wazeInstalado)) {
        return const [AppDeRota.googleMaps, AppDeRota.waze];
      }
    } catch (_) {
      // Sem resposta do sistema, o Google Maps continua valendo.
    }
    return const [AppDeRota.googleMaps];
  }

  Future<bool> abrir(AppDeRota app, double lat, double lng) async {
    final uri = switch (app) {
      AppDeRota.googleMaps => googleMaps(lat, lng),
      AppDeRota.waze => waze(lat, lng),
    };
    try {
      return await navegador.abrir(uri);
    } catch (_) {
      return false;
    }
  }
}
