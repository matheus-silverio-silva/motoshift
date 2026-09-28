import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/services/localizacao_service.dart';
import 'package:moto_shift/views/detalhe_turno/detalhe_turno_conteudo.dart';
import 'package:moto_shift/views/meus_turnos/filtros_turnos_sheet.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/widgets/mapa_raio.dart';

import '../test_helpers.dart';
import 'fonte_falsa.dart';

/// "Perto de mim" na lista de turnos do entregador — suspeitas 4, 8 e 9.
///
/// 4. Se a busca com filtro falhava, a tela trazia a lista SEM filtro e
///    continuava dizendo "perto de mim".
/// 8. O raio de entrega do turno e a distância até o entregador apareciam os
///    dois como "raio" — e o card mostrava "8 km" sem dizer qual dos dois.
/// 9. A distância do card, do detalhe e do pino precisa ser a mesma, e a do
///    backend.
void main() {
  setUpAll(setupGoldenTests);

  // O entregador no Água Verde.
  final gps = LocalizacaoService(fonte: FonteFalsa(lat: -25.4560, lng: -49.2820));

  Future<void> ligarPertoDeMim(WidgetTester tester) async {
    await tester.tap(find.byType(Switch).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('4 — busca com filtro que falha', () {
    testWidgets('mostra o erro com "Tentar de novo", nunca a lista sem filtro',
        (tester) async {
      final api = _ApiDeDistancia()..turnosFalsos.falharFiltro = true;
      await pumpGolden(tester,
          child: const MeusTurnosScreen(), apiFake: api, localizacao: gps);

      // Antes de ligar o filtro, a lista sem filtro é a certa.
      expect(find.textContaining('Turno Tarde — Hamburgueria'), findsOneWidget);

      await ligarPertoDeMim(tester);

      expect(find.text('Não foi possível buscar os turnos perto de você.'),
          findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.textContaining('Turno Tarde — Hamburgueria'), findsNothing,
          reason: 'a lista sem filtro não pode aparecer como se fosse "perto de mim"');
      expect(api.turnosFalsos.chamadasSemFiltro, 1,
          reason: 'só a carga inicial; a falha não recarrega sem filtro');

      // A rede volta: "Tentar de novo" busca com o filtro.
      api.turnosFalsos.falharFiltro = false;
      await tester.tap(find.text('Tentar de novo'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Não foi possível buscar os turnos perto de você.'),
          findsNothing);
      expect(find.textContaining('Perto — Farmácia'), findsOneWidget);
    });
  });

  group('9 — uma distância só, a do backend', () {
    testWidgets('card e pino mostram a distanciaKm que veio, sem recalcular',
        (tester) async {
      final api = _ApiDeDistancia();
      await pumpGolden(tester,
          child: const MeusTurnosScreen(), apiFake: api, localizacao: gps);
      await ligarPertoDeMim(tester);

      // O turno está, pelas coordenadas, a ~10 km; o backend disse 2,3 km.
      // Se o app recalculasse, mostraria outro número.
      expect(find.textContaining('a 2,3 km'), findsWidgets);
      // A linha do card corta com reticências: a distância vem antes da
      // região, senão some no celular.
      final linha = tester
          .widgetList<Text>(find.textContaining('Perto — Farmácia'))
          .first
          .data!;
      expect(linha.indexOf('a 2,3 km'), lessThan(linha.indexOf('Centro Cívico')));
      final pinos = tester
          .widget<MapaRaio>(find.byType(MapaRaio).first)
          .pontos
          .map((p) => p.rotulo)
          .toList();
      expect(pinos, contains('R\$ 110 · 2,3 km'));
    });

    testWidgets('o detalhe mostra a mesma distância do card', (tester) async {
      await pumpGolden(tester,
          child: Scaffold(body: DetalheTurnoConteudo(turno: _pertoDaFarmacia())));

      expect(find.text('a 2,3 km'), findsOneWidget);
      expect(find.text('DISTÂNCIA DE VOCÊ'), findsOneWidget);
    });

    testWidgets('sem distância (busca sem posição), o detalhe não inventa uma',
        (tester) async {
      await pumpGolden(tester,
          child: Scaffold(
              body: DetalheTurnoConteudo(turno: fakeTurnosDisponiveis().first)));

      expect(find.text('DISTÂNCIA DE VOCÊ'), findsNothing);
    });
  });

  group('8 — dois raios, dois nomes', () {
    testWidgets('sem posição, o card diz que o número é a área de entrega',
        (tester) async {
      await pumpGolden(tester, child: const MeusTurnosScreen(), localizacao: gps);

      expect(find.textContaining('entrega até 8 km'), findsOneWidget);
      // O "· 8 km" solto era o raio de entrega com cara de distância.
      expect(find.textContaining(RegExp(r'· 8 km')), findsNothing);
    });

    testWidgets('a folha de filtros chama o raio do turno de área de entrega',
        (tester) async {
      await pumpGolden(tester,
          child: Scaffold(
            body: FiltrosTurnosSheet(
              horarioInicio: null,
              horarioFim: null,
              diaSemana: null,
              raioMax: null,
              ordenarPor: 'dataInicio',
              onAplicar: (_, __, ___, ____, _____) {},
              onLimpar: () {},
            ),
          ));

      expect(find.text('Raio máximo de entrega'), findsNothing);
      expect(find.text('Área de entrega do turno'), findsOneWidget);
      expect(find.textContaining('não é a distância até você'), findsOneWidget);
    });

    testWidgets('"Maior valor" pede do maior para o menor', (tester) async {
      String? ordem;
      await pumpGolden(tester,
          child: Scaffold(
            body: FiltrosTurnosSheet(
              horarioInicio: null,
              horarioFim: null,
              diaSemana: null,
              raioMax: null,
              ordenarPor: 'dataInicio',
              onAplicar: (_, __, ___, ____, o) => ordem = o,
              onLimpar: () {},
            ),
          ));

      await tester.tap(find.text('Maior valor'));
      await tester.pump();
      await tester.tap(find.text('Aplicar filtros'));
      await tester.pump();

      expect(ordem, 'valorDesc');
    });

    testWidgets('a ordem que abre marcada é a que a lista tem: mais cedo primeiro',
        (tester) async {
      await pumpGolden(tester, child: const MeusTurnosScreen(), localizacao: gps);

      await tester.tap(find.text('Filtrar'));
      await tester.pumpAndSettle();

      final maisCedo = tester.widget<RadioListTile<String>>(
          find.widgetWithText(RadioListTile<String>, 'Mais cedo'));
      expect(maisCedo.checked, isTrue);
    });
  });
}

/// Farmácia a ~10 km do entregador pelas coordenadas — mas o backend mediu
/// 2,3 km. A diferença de propósito é o que denuncia um recálculo no app.
Turno _pertoDaFarmacia() {
  final amanha = DateTime.now().add(const Duration(days: 1));
  return Turno(
    id: 301,
    lojistId: 3,
    titulo: 'Perto — Farmácia',
    regiao: 'Centro Cívico, Curitiba',
    dataInicio: DateTime(amanha.year, amanha.month, amanha.day, 8),
    dataFim: DateTime(amanha.year, amanha.month, amanha.day, 12),
    valorEstimado: 110,
    raioEntregaKm: 6,
    latitude: -25.3660,
    longitude: -49.2820,
    distanciaKm: 2.3,
  );
}

class _TurnosDeDistancia extends FakeTurnoApi {
  bool falharFiltro = false;
  int chamadasSemFiltro = 0;
  final List<String?> ordens = [];

  @override
  Future<List<Turno>> listarTurnosDisponiveis({DateTime? data}) async {
    chamadasSemFiltro++;
    return fakeTurnosDisponiveis();
  }

  @override
  Future<List<Turno>> listarTurnosDisponiveisComFiltros({
    String? horarioInicio,
    String? horarioFim,
    int? diaSemana,
    double? raioMaxKm,
    String? dataInicio,
    String? dataFim,
    String? ordenarPor,
    double? lat,
    double? lng,
    double? raioKm,
  }) async {
    ordens.add(ordenarPor);
    if (falharFiltro) {
      throw const ApiException(503, 'Serviço indisponível');
    }
    return [_pertoDaFarmacia()];
  }
}

class _ApiDeDistancia extends FakeApiService {
  final _TurnosDeDistancia turnosFalsos = _TurnosDeDistancia();

  @override
  TurnoApi get turnos => turnosFalsos;
}
