// Captura do shell responsivo nas três larguras — ferramenta de conferência
// visual, não faz parte da suíte. Gerar os PNGs (em capturas/, fora do git):
//   flutter test test/dev_capture/shell_capture_test.dart --update-goldens --dart-define=CAPTURE=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/dev/shell_preview_main.dart';
import 'package:moto_shift/models/usuario.dart';

import '../test_helpers.dart';

// Sem o dart-define os testes ficam skipped: os PNGs de referência são
// gerados sob demanda e não são versionados.
const _capture = bool.fromEnvironment('CAPTURE');

void main() {
  setUpAll(setupGoldenTests);

  const tamanhos = {
    'mobile_390': Size(390, 844),
    'tablet_800': Size(800, 1024),
    'desktop_1440': Size(1440, 1024),
  };

  for (final entry in tamanhos.entries) {
    testWidgets('shell lojista ${entry.key}', (tester) async {
      await pumpGolden(
        tester,
        child: const ShellPreviewScreen(),
        tipoUsuario: TipoUsuario.lojista,
        viewport: entry.value,
      );
      await expectLater(
        find.byType(ShellPreviewScreen),
        matchesGoldenFile('capturas/shell_lojista_${entry.key}.png'),
      );
    }, skip: !_capture);
  }

  testWidgets('shell motoboy desktop_1440', (tester) async {
    await pumpGolden(
      tester,
      child: const ShellPreviewScreen(),
      tipoUsuario: TipoUsuario.motoboy,
      viewport: const Size(1440, 1024),
    );
    await expectLater(
      find.byType(ShellPreviewScreen),
      matchesGoldenFile('capturas/shell_motoboy_desktop_1440.png'),
    );
  }, skip: !_capture);
}
