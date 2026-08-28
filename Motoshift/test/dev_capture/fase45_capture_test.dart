// Captura das telas novas (Fase 4) e do refinamento mobile (Fase 5).
//   flutter test test/dev_capture/fase45_capture_test.dart --update-goldens --dart-define=CAPTURE=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/avaliar_entregadores/avaliar_entregadores_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/views/notificacoes/notificacoes_screen.dart';
import 'package:moto_shift/views/saldo_lojista/saldo_lojista_screen.dart';

import '../test_helpers.dart';

const _capture = bool.fromEnvironment('CAPTURE');
const _desktop = Size(1440, 1024);
const _mobile = Size(390, 844);

void main() {
  setUpAll(setupGoldenTests);

  testWidgets('17 notificacoes desktop', (t) async {
    await pumpGolden(t,
        child: const NotificacoesScreen(),
        tipoUsuario: TipoUsuario.lojista,
        viewport: _desktop);
    await expectLater(find.byType(NotificacoesScreen),
        matchesGoldenFile('capturas/f4_notificacoes_desktop.png'));
  }, skip: !_capture);

  testWidgets('17 notificacoes mobile', (t) async {
    await pumpGolden(t,
        child: const NotificacoesScreen(), viewport: _mobile);
    await expectLater(find.byType(NotificacoesScreen),
        matchesGoldenFile('capturas/f4_notificacoes_mobile.png'));
  }, skip: !_capture);

  testWidgets('18 filtro por raio mobile', (t) async {
    await pumpGolden(t, child: const MeusTurnosScreen(), viewport: _mobile);
    await expectLater(find.byType(MeusTurnosScreen),
        matchesGoldenFile('capturas/f4_raio_mobile.png'));
  }, skip: !_capture);

  testWidgets('19 avaliar entregadores desktop', (t) async {
    await pumpGolden(
      t,
      child: const AvaliarEntregadoresScreen(),
      tipoUsuario: TipoUsuario.lojista,
      viewport: _desktop,
      argumentos: const AvaliarEntregadoresArgs(
        turnoId: 301,
        tituloTurno: 'Sexta cheia · Rebouças',
      ),
    );
    await expectLater(find.byType(AvaliarEntregadoresScreen),
        matchesGoldenFile('capturas/f4_avaliar_entregadores.png'));
  }, skip: !_capture);

  testWidgets('21 saldo lojista desktop', (t) async {
    await pumpGolden(t,
        child: const SaldoLojistaScreen(),
        tipoUsuario: TipoUsuario.lojista,
        viewport: _desktop);
    await expectLater(find.byType(SaldoLojistaScreen),
        matchesGoldenFile('capturas/f4_saldo_lojista.png'));
  }, skip: !_capture);

  testWidgets('fase5 dashboard motoboy mobile refinado', (t) async {
    await pumpGolden(t,
        child: const DashboardMotoboyScreen(), viewport: _mobile);
    await expectLater(find.byType(DashboardMotoboyScreen),
        matchesGoldenFile('capturas/f5_dash_motoboy_mobile.png'));
  }, skip: !_capture);
}
