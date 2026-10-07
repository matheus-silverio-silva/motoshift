// Goldens da tela de resultado (RF13 / SCRUM-47): a DRE do entregador com
// lucro, a do entregador com prejuízo e a do lojista — cada uma no celular e
// no desktop.
//
// O "agora" é a âncora dos goldens (19/08/2026) e os números são fixtures
// (test_helpers.dart): a tela não lê relógio nem rede.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/resultado/resultado_screen.dart';

import '../test_helpers.dart';

/// O mesmo viewport de desktop dos testes do shell (master_detail_test).
const _desktop = Size(1440, 1024);

void main() {
  setUpAll(setupGoldenTests);

  final casos = <({String nome, String arquivo, TipoUsuario papel, bool prejuizo})>[
    (
      nome: 'entregador com lucro',
      arquivo: 'resultado_motoboy_lucro',
      papel: TipoUsuario.motoboy,
      prejuizo: false,
    ),
    (
      nome: 'entregador com prejuízo',
      arquivo: 'resultado_motoboy_prejuizo',
      papel: TipoUsuario.motoboy,
      prejuizo: true,
    ),
    (
      nome: 'lojista',
      arquivo: 'resultado_lojista',
      papel: TipoUsuario.lojista,
      prejuizo: false,
    ),
  ];

  for (final caso in casos) {
    testWidgets('ResultadoScreen — ${caso.nome} (celular)', (tester) async {
      await pumpGolden(
        tester,
        child: ResultadoScreen(agora: dataAncoraGolden),
        tipoUsuario: caso.papel,
        apiFake: FakeApiService(
            tipoUsuario: caso.papel, resultadoComPrejuizo: caso.prejuizo),
      );
      await expectLater(
        find.byType(ResultadoScreen),
        matchesGoldenFile('goldens/${caso.arquivo}.png'),
      );
    });

    testWidgets('ResultadoScreen — ${caso.nome} (desktop)', (tester) async {
      await pumpGolden(
        tester,
        child: ResultadoScreen(agora: dataAncoraGolden),
        tipoUsuario: caso.papel,
        apiFake: FakeApiService(
            tipoUsuario: caso.papel, resultadoComPrejuizo: caso.prejuizo),
        viewport: _desktop,
      );
      await expectLater(
        find.byType(ResultadoScreen),
        matchesGoldenFile('goldens/${caso.arquivo}_desktop.png'),
      );
    });
  }
}
