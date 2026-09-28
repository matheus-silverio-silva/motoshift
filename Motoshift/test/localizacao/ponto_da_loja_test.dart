import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/auth_api.dart';
import 'package:moto_shift/services/localizacao_service.dart';
import 'package:moto_shift/views/dados_pessoais/dados_pessoais_screen.dart';
import 'package:moto_shift/widgets/mapa_raio.dart';

import '../test_helpers.dart';
import 'fonte_falsa.dart';

/// A loja marca o ponto no mapa uma vez, em "Dados pessoais" — e é de lá que
/// todo turno dela parte (suspeita 2).
void main() {
  setUpAll(setupGoldenTests);

  final mapa = find.byKey(const Key('mapa-ponto-da-loja'));

  Future<void> salvar(WidgetTester tester) async {
    final botao = find.text('Salvar alterações');
    await tester.ensureVisible(botao);
    await tester.pumpAndSettle();
    await tester.tap(botao);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('tocar o mapa e salvar grava o ponto da loja', (tester) async {
    final api = _ApiQueGuardaPerfil();
    await pumpGolden(tester,
        child: const DadosPessoaisScreen(),
        tipoUsuario: TipoUsuario.lojista,
        apiFake: api);

    expect(find.textContaining('Sem ponto marcado'), findsOneWidget);

    tester.widget<MapaRaio>(mapa).onTapMapa!(const LatLng(-25.4561, -49.2821));
    await tester.pump();
    expect(find.textContaining('Ponto marcado'), findsOneWidget);

    await salvar(tester);

    expect(api.perfis.enviados.single['latitude'], -25.4561);
    expect(api.perfis.enviados.single['longitude'], -49.2821);
  });

  testWidgets('"Estou na loja" usa o GPS; se falhar, diz por quê', (tester) async {
    final fonte = FonteFalsa(lat: -25.44, lng: -49.26);
    await pumpGolden(tester,
        child: const DadosPessoaisScreen(),
        tipoUsuario: TipoUsuario.lojista,
        localizacao: LocalizacaoService(fonte: fonte));

    await tester.ensureVisible(find.textContaining('Estou na loja'));
    await tester.tap(find.textContaining('Estou na loja'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<MapaRaio>(mapa).centro, const LatLng(-25.44, -49.26));

    fonte.ligado = false;
    await tester.tap(find.textContaining('Estou na loja'));
    await tester.pump();
    await tester.pump();
    expect(find.text(FalhaLocalizacao.servicoDesligado.mensagem), findsOneWidget);
  });

  testWidgets('o entregador não tem ponto de loja', (tester) async {
    await pumpGolden(tester, child: const DadosPessoaisScreen());

    expect(mapa, findsNothing);
    expect(find.text('Ponto da loja no mapa'), findsNothing);
  });
}

class _PerfisGuardados extends FakeAuthApi {
  final List<Map<String, dynamic>> enviados = [];

  @override
  Future<Usuario> atualizarPerfil(int id, Map<String, dynamic> campos) async {
    enviados.add(campos);
    return fakeLojista().copyWith(
      latitude: campos['latitude'] as double?,
      longitude: campos['longitude'] as double?,
    );
  }
}

class _ApiQueGuardaPerfil extends FakeApiService {
  _ApiQueGuardaPerfil() : super(tipoUsuario: TipoUsuario.lojista);

  final _PerfisGuardados perfis = _PerfisGuardados();

  @override
  AuthApi get auth => perfis;
}
