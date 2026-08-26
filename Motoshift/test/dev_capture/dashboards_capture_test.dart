// Captura dos dashboards (Fase 1) nas três larguras — conferência visual,
// não faz parte da suíte. Gerar:
//   flutter test test/dev_capture/dashboards_capture_test.dart --update-goldens --dart-define=CAPTURE=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';

import '../test_helpers.dart';

const _capture = bool.fromEnvironment('CAPTURE');

const _tamanhos = {
  'mobile_390': Size(390, 844),
  'tablet_800': Size(800, 1024),
  'desktop_1440': Size(1440, 1024),
};

void main() {
  setUpAll(setupGoldenTests);

  for (final entry in _tamanhos.entries) {
    testWidgets('dashboard lojista ${entry.key}', (tester) async {
      await pumpGolden(
        tester,
        child: const DashboardLojistScreen(),
        tipoUsuario: TipoUsuario.lojista,
        viewport: entry.value,
      );
      await expectLater(
        find.byType(DashboardLojistScreen),
        matchesGoldenFile('capturas/dash_lojista_${entry.key}.png'),
      );
    }, skip: !_capture);

    testWidgets('dashboard motoboy ${entry.key}', (tester) async {
      await pumpGolden(
        tester,
        child: const DashboardMotoboyScreen(),
        viewport: entry.value,
      );
      await expectLater(
        find.byType(DashboardMotoboyScreen),
        matchesGoldenFile('capturas/dash_motoboy_${entry.key}.png'),
      );
    }, skip: !_capture);
  }
}
