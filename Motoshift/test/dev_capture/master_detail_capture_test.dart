// Captura do master-detail (Fase 2) — conferência visual, não faz parte da
// suíte. Gerar:
//   flutter test test/dev_capture/master_detail_capture_test.dart --update-goldens --dart-define=CAPTURE=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';

import '../test_helpers.dart';

const _capture = bool.fromEnvironment('CAPTURE');

const _desktop = Size(1440, 1024);
const _mobile = Size(390, 844);

void main() {
  setUpAll(setupGoldenTests);

  testWidgets('turnos disponiveis desktop — nada selecionado', (tester) async {
    await pumpGolden(
      tester,
      child: const MeusTurnosScreen(),
      viewport: _desktop,
    );
    await expectLater(
      find.byType(MeusTurnosScreen),
      matchesGoldenFile('capturas/md_disponiveis_desktop_vazio.png'),
    );
  }, skip: !_capture);

  testWidgets('turnos disponiveis desktop — com selecao', (tester) async {
    await pumpGolden(
      tester,
      child: const MeusTurnosScreen(),
      viewport: _desktop,
      // id 101 — primeiro turno de fakeTurnosDisponiveis()
      turnoSelecionado: 101,
    );
    await expectLater(
      find.byType(MeusTurnosScreen),
      matchesGoldenFile('capturas/md_disponiveis_desktop_selecionado.png'),
    );
  }, skip: !_capture);

  testWidgets('turnos disponiveis mobile', (tester) async {
    await pumpGolden(
      tester,
      child: const MeusTurnosScreen(),
      viewport: _mobile,
    );
    await expectLater(
      find.byType(MeusTurnosScreen),
      matchesGoldenFile('capturas/md_disponiveis_mobile.png'),
    );
  }, skip: !_capture);

  testWidgets('turnos lojista desktop — com selecao', (tester) async {
    await pumpGolden(
      tester,
      child: const TurnosLojistaListaScreen(),
      tipoUsuario: TipoUsuario.lojista,
      viewport: _desktop,
      // id 301 — turno aceito de fakeTurnosLojista()
      turnoSelecionado: 301,
    );
    await expectLater(
      find.byType(TurnosLojistaListaScreen),
      matchesGoldenFile('capturas/md_lojista_desktop_selecionado.png'),
    );
  }, skip: !_capture);

  testWidgets('turnos lojista mobile', (tester) async {
    await pumpGolden(
      tester,
      child: const TurnosLojistaListaScreen(),
      tipoUsuario: TipoUsuario.lojista,
      viewport: _mobile,
    );
    await expectLater(
      find.byType(TurnosLojistaListaScreen),
      matchesGoldenFile('capturas/md_lojista_mobile.png'),
    );
  }, skip: !_capture);
}
