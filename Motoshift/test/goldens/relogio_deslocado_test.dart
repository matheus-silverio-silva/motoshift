// A pergunta que os goldens sozinhos não respondem: a renderização depende do
// relógio da máquina?
//
// Três vezes esta suíte amanheceu vermelha sem ninguém tocar em código — a
// agenda no dia 20, os dashboards às 18h de um dia qualquer, o gráfico do
// motoboy na virada de 27 para 28. Cada vez, a correção foi injetar a data
// naquele ponto, e a verificação foi "rodei hoje e passou" — que é exatamente
// a evidência que falhou nas três vezes.
//
// Este arquivo troca isso por uma pergunta que se responde em segundos: as
// telas leem `clock.now()`, então `withClock` desloca o relógio dentro do
// teste e os MESMOS goldens são comparados. Se algum ponto ainda ler o
// calendário de verdade, o pixel muda e o teste acusa aqui — não daqui a um
// mês, na máquina de outra pessoa.

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/views/agenda/agenda_screen.dart';
import 'package:moto_shift/views/carteira/carteira_screen.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/historico_turnos/historico_turnos_screen.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';

import '../test_helpers.dart';

/// +1 e +2 pegam a virada do dia e do dia da semana; +30 pega a virada do mês,
/// que é o que faria o "X meses na plataforma" do perfil andar.
const _deslocamentos = [1, 2, 30];

void main() {
  setUpAll(setupGoldenTests);

  /// Renderiza [tela] com o relógio deslocado e compara com o MESMO golden
  /// gravado sob o relógio real.
  Future<void> estavelEm(
    WidgetTester tester,
    int dias, {
    required Widget tela,
    required Type tipo,
    required String golden,
    TipoUsuario usuario = TipoUsuario.motoboy,
    ApiService? apiFake,
  }) async {
    await withClock(Clock.fixed(clock.now().add(Duration(days: dias))),
        () async {
      await pumpGolden(
        tester,
        child: tela,
        tipoUsuario: usuario,
        apiFake: apiFake,
      );
      await expectLater(
        find.byType(tipo),
        matchesGoldenFile('goldens/$golden.png'),
      );
    });
  }

  for (final dias in _deslocamentos) {
    group('relógio +$dias dia(s)', () {
      testWidgets('agenda (motoboy)', (t) async {
        await estavelEm(t, dias,
            tela: AgendaScreen(agora: dataAncoraGolden),
            tipo: AgendaScreen,
            golden: 'agenda_screen_motoboy');
      });

      testWidgets('dashboard do motoboy', (t) async {
        await estavelEm(t, dias,
            tela: DashboardMotoboyScreen(agora: dataAncoraGolden),
            tipo: DashboardMotoboyScreen,
            apiFake: FakeApiDatasFixas(),
            golden: 'dashboard_motoboy_screen');
      });

      testWidgets('dashboard do lojista', (t) async {
        await estavelEm(t, dias,
            tela: DashboardLojistScreen(agora: dataAncoraGolden),
            tipo: DashboardLojistScreen,
            usuario: TipoUsuario.lojista,
            apiFake: FakeApiDatasFixas(),
            golden: 'dashboard_lojista_screen');
      });

      testWidgets('turnos disponíveis', (t) async {
        await estavelEm(t, dias,
            tela: MeusTurnosScreen(agora: dataAncoraGolden),
            tipo: MeusTurnosScreen,
            apiFake: FakeApiDatasFixas(),
            golden: 'meus_turnos_screen');
      });

      testWidgets('carteira', (t) async {
        await estavelEm(t, dias,
            tela: CarteiraScreen(agora: dataAncoraGolden),
            tipo: CarteiraScreen,
            golden: 'carteira_screen');
      });

      testWidgets('perfil (motoboy)', (t) async {
        await estavelEm(t, dias,
            tela: PerfilScreen(agora: dataAncoraGolden),
            tipo: PerfilScreen,
            golden: 'perfil_screen_motoboy');
      });

      testWidgets('histórico (motoboy)', (t) async {
        await estavelEm(t, dias,
            tela: const HistoricoTurnosScreen(),
            tipo: HistoricoTurnosScreen,
            apiFake: FakeApiHistorico(),
            golden: 'historico_turnos_motoboy');
      });

      testWidgets('turnos do lojista', (t) async {
        await estavelEm(t, dias,
            tela: const TurnosLojistaListaScreen(),
            tipo: TurnosLojistaListaScreen,
            usuario: TipoUsuario.lojista,
            golden: 'turnos_lojista_lista_screen');
      });
    });
  }
}
