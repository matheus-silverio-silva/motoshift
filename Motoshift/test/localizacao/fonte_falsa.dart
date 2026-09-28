import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:moto_shift/services/localizacao_service.dart';

/// O GPS dos testes: responde o que o teste mandar, quando o teste mandar.
///
/// [posicaoPendente] deixa a resposta do GPS na mão do teste — é o que permite
/// reproduzir "o GPS respondeu depois do toque no mapa". [permissaoPendente]
/// reproduz o aviso de permissão do navegador que ninguém clicou.
class FonteFalsa extends FonteDePosicao {
  FonteFalsa({
    this.lat = -25.4560,
    this.lng = -49.2820,
    this.ligado = true,
    this.permissaoAtual = LocationPermission.whileInUse,
    this.web = false,
    this.seguro = true,
    this.falhar = false,
    this.ultima,
  });

  double lat;
  double lng;
  bool ligado;
  LocationPermission permissaoAtual;
  bool web;
  bool seguro;
  bool falhar;
  Position? ultima;

  /// Quando não nulo, `posicao()` só responde quando o teste completar.
  Completer<Position>? posicaoPendente;

  /// Quando não nulo, pedir permissão nunca responde sozinho.
  Completer<LocationPermission>? permissaoPendente;

  int chamadasDePosicao = 0;
  int consultasAoServico = 0;

  @override
  Future<bool> servicoLigado() async {
    consultasAoServico++;
    return ligado;
  }

  @override
  Future<LocationPermission> permissao() async => permissaoAtual;

  @override
  Future<LocationPermission> pedirPermissao() =>
      permissaoPendente?.future ?? Future.value(permissaoAtual);

  @override
  Future<Position> posicao(LocationSettings ajustes) {
    chamadasDePosicao++;
    if (falhar) return Future.error(Exception('GPS quebrado'));
    final pendente = posicaoPendente;
    if (pendente != null) return pendente.future;
    return Future.value(posicaoEm(lat, lng));
  }

  @override
  Future<Position?> ultimaConhecida() async => ultima;

  @override
  Future<void> abrirConfiguracoes() async {}

  @override
  bool get ehWeb => web;

  @override
  bool get contextoSeguro => seguro;
}

Position posicaoEm(double lat, double lng, {DateTime? quando}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: quando ?? DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
