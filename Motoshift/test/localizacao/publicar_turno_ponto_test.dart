import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/services/geo_referencia.dart';
import 'package:moto_shift/services/localizacao_service.dart';
import 'package:moto_shift/views/agendar_turno/agendar_turno_screen.dart';
import 'package:moto_shift/widgets/mapa_raio.dart';

import '../test_helpers.dart';
import 'fonte_falsa.dart';

/// De onde o turno parte — suspeitas 1, 2 e 3 da auditoria de localização.
///
/// 1. O GPS respondia depois do toque no mapa e sobrescrevia o ponto escolhido.
/// 2. O pino era o GPS de onde o lojista estivesse publicando, enquanto o
///    endereço escrito era o da loja.
/// 3. Sem cidade conhecida e sem GPS, o turno era publicado no marco zero de
///    Curitiba sem ninguém ter confirmado aquele ponto.
void main() {
  setUpAll(setupGoldenTests);

  const loja = LatLng(-25.4560, -49.2820); // Av. Água Verde, 1200
  const tocado = LatLng(-25.5000, -49.3000);
  const casaDoLojista = LatLng(-23.5505, -46.6333); // o GPS, bem longe da loja

  MapaRaio mapa(WidgetTester tester) =>
      tester.widget<MapaRaio>(find.byType(MapaRaio).first);

  testWidgets('1 — o GPS que responde depois do toque não move o ponto escolhido',
      (tester) async {
    final fonte = FonteFalsa()..posicaoPendente = Completer<Position>();
    await pumpGolden(
      tester,
      child: const AgendarTurnoScreen(),
      tipoUsuario: TipoUsuario.lojista,
      usuario: _lojista(),
      localizacao: LocalizacaoService(fonte: fonte),
    );

    // O lojista toca o mapa enquanto o GPS ainda procura…
    mapa(tester).onTapMapa!(tocado);
    await tester.pump();
    // …e o GPS responde depois, com a posição de onde ele está.
    fonte.posicaoPendente!
        .complete(posicaoEm(casaDoLojista.latitude, casaDoLojista.longitude));
    await tester.pump();
    await tester.pump();

    expect(mapa(tester).centro, tocado);
    expect(find.text('Ponto escolhido por você no mapa.'), findsOneWidget);
  });

  testWidgets('2 — com a loja marcada, o turno parte da loja e o GPS nem é consultado',
      (tester) async {
    final fonte = FonteFalsa(lat: casaDoLojista.latitude, lng: casaDoLojista.longitude);
    final api = _ApiQueGrava();
    await pumpGolden(
      tester,
      child: const AgendarTurnoScreen(),
      tipoUsuario: TipoUsuario.lojista,
      usuario: _lojista(ponto: loja),
      apiFake: api,
      localizacao: LocalizacaoService(fonte: fonte),
    );

    expect(mapa(tester).centro, loja);
    expect(fonte.chamadasDePosicao, 0);
    expect(find.textContaining('Ponto da sua loja'), findsOneWidget);

    await _preencherEPublicar(tester);
    await _confirmarCusto(tester);

    expect(api.gravados.turnos, hasLength(1));
    final turno = api.gravados.turnos.single;
    expect(LatLng(turno.latitude!, turno.longitude!), loja);
    expect(turno.endereco, _lojista().enderecoComercial);
  });

  testWidgets('2 — sem a loja marcada, o GPS é a segunda opção', (tester) async {
    final fonte = FonteFalsa(lat: -25.44, lng: -49.27);
    await pumpGolden(
      tester,
      child: const AgendarTurnoScreen(),
      tipoUsuario: TipoUsuario.lojista,
      usuario: _lojista(),
      localizacao: LocalizacaoService(fonte: fonte),
    );

    expect(mapa(tester).centro, const LatLng(-25.44, -49.27));
    expect(find.textContaining('Posição atual do aparelho'), findsOneWidget);
  });

  testWidgets('3 — sem cidade conhecida e sem GPS, publicar pede o ponto antes',
      (tester) async {
    final api = _ApiQueGrava();
    await pumpGolden(
      tester,
      child: const AgendarTurnoScreen(),
      tipoUsuario: TipoUsuario.lojista,
      usuario: _lojista(cidade: 'Cidade Que Não Existe'),
      apiFake: api,
      localizacao: LocalizacaoService(fonte: FonteFalsa(ligado: false)),
    );
    expect(mapa(tester).centro, GeoReferencia.padrao);

    await _preencherEPublicar(tester);

    expect(find.text('Confirme o ponto de partida'), findsOneWidget);
    expect(api.gravados.turnos, isEmpty, reason: 'nada publicado sem o ponto');

    // "Marcar no mapa" volta ao formulário, sem publicar.
    await tester.tap(find.text('Marcar no mapa'));
    await _esperar(tester);
    expect(api.gravados.turnos, isEmpty);

    // Com o ponto tocado no mapa, publica sem perguntar de novo.
    mapa(tester).onTapMapa!(tocado);
    await tester.pump();
    await _publicar(tester);
    expect(find.text('Confirme o ponto de partida'), findsNothing);
    await _confirmarCusto(tester);

    final turno = api.gravados.turnos.single;
    expect(LatLng(turno.latitude!, turno.longitude!), tocado);
  });

  testWidgets('3 — o lojista pode confirmar o ponto sugerido em vez de tocar o mapa',
      (tester) async {
    final api = _ApiQueGrava();
    await pumpGolden(
      tester,
      child: const AgendarTurnoScreen(),
      tipoUsuario: TipoUsuario.lojista,
      usuario: _lojista(cidade: 'Cidade Que Não Existe'),
      apiFake: api,
      localizacao: LocalizacaoService(fonte: FonteFalsa(ligado: false)),
    );

    await _preencherEPublicar(tester);
    await tester.tap(find.text('Usar este ponto'));
    await _esperar(tester);
    await _confirmarCusto(tester);

    expect(api.gravados.turnos, hasLength(1));
  });
}

// ── apoio ────────────────────────────────────────────────────────────────────

Usuario _lojista({LatLng? ponto, String cidade = 'Curitiba'}) => fakeLojista().copyWith(
      cidade: cidade,
      latitude: ponto?.latitude,
      longitude: ponto?.longitude,
    );

/// Data de amanhã, 08:00–12:00 e R$ 120 — o mínimo para o formulário passar.
Future<void> _preencherEPublicar(WidgetTester tester) async {
  await tester.tap(find.text('Selecionar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  for (var i = 0; i < 2; i++) {
    await tester.tap(find.text('--:--').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  final valor = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0,00');
  await tester.enterText(valor, '120');
  await tester.pump();

  await _publicar(tester);
}

Future<void> _publicar(WidgetTester tester) async {
  final botao = find.text('Publicar Turno');
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  // Sem pumpAndSettle: o botão fica girando atrás do diálogo, e um spinner
  // nunca "assenta".
  await _esperar(tester);
}

Future<void> _confirmarCusto(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('publicar-confirmar')));
  await _esperar(tester);
}

Future<void> _esperar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class _TurnosGravados extends FakeTurnoApi {
  final List<Turno> turnos = [];

  @override
  Future<Turno> criarTurno(Turno turno) async {
    turnos.add(turno);
    return turno;
  }
}

class _ApiQueGrava extends FakeApiService {
  _ApiQueGrava() : super(tipoUsuario: TipoUsuario.lojista);

  final _TurnosGravados gravados = _TurnosGravados();

  @override
  TurnoApi get turnos => gravados;
}
