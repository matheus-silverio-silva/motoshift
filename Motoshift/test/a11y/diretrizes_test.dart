// As diretrizes de acessibilidade do próprio Flutter, nas telas por onde todo
// mundo passa: login, os dois painéis e o detalhe do turno (SCRUM-40).
//
// O `alvo_de_toque_test.dart` mede o TAMANHO do que é clicável. Aqui são as
// duas perguntas que ele não faz:
//
//   labeledTapTargetGuideline — tudo o que responde a toque tem um nome? Um
//     ícone clicável sem rótulo é, para o leitor de tela, "botão" e mais nada.
//   textContrastGuideline — o texto tem contraste suficiente com o fundo?
//     É a regra do WCAG 2.1 nível AA: 4,5:1 para texto comum e 3:1 para texto
//     grande (18 pt, ou 14 pt em negrito).
//
// As duas medem a tela DESENHADA, com as fontes e as cores do app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/detalhe_turno/detalhe_turno_screen.dart';
import 'package:moto_shift/views/login/login_screen.dart';
import 'package:moto_shift/views/resultado/resultado_screen.dart';
import 'package:moto_shift/views/turno_lojista/turno_lojista_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  final telas = <({
    String nome,
    TipoUsuario papel,
    Widget Function() tela,
    Object? Function() argumentos,
  })>[
    (
      nome: 'login',
      papel: TipoUsuario.motoboy,
      tela: () => const LoginScreen(),
      argumentos: () => null,
    ),
    (
      nome: 'painel do entregador',
      papel: TipoUsuario.motoboy,
      tela: () => DashboardMotoboyScreen(agora: dataAncoraGolden),
      argumentos: () => null,
    ),
    (
      nome: 'painel do lojista',
      papel: TipoUsuario.lojista,
      tela: () => DashboardLojistScreen(agora: dataAncoraGolden),
      argumentos: () => null,
    ),
    (
      nome: 'detalhe do turno (entregador)',
      papel: TipoUsuario.motoboy,
      tela: () => const DetalheTurnoScreen(),
      argumentos: () => fakeTurnosDisponiveis().first,
    ),
    (
      nome: 'detalhe do turno (lojista)',
      papel: TipoUsuario.lojista,
      tela: () => const TurnoLojistScreen(),
      argumentos: () => fakeTurnosLojista().first,
    ),
    // A tela de resultado (SCRUM-47) nasceu depois desta lista, e entra nela:
    // a faixa de lucro e a de prejuízo têm fundo colorido, que é onde o
    // contraste costuma falhar.
    (
      nome: 'resultado (entregador)',
      papel: TipoUsuario.motoboy,
      tela: () => ResultadoScreen(agora: dataAncoraGolden),
      argumentos: () => null,
    ),
    (
      nome: 'resultado (lojista)',
      papel: TipoUsuario.lojista,
      tela: () => ResultadoScreen(agora: dataAncoraGolden),
      argumentos: () => null,
    ),
  ];

  for (final t in telas) {
    group(t.nome, () {
      Future<void> montar(WidgetTester tester) => pumpGolden(
            tester,
            child: t.tela(),
            tipoUsuario: t.papel,
            argumentos: t.argumentos(),
            viewport: const Size(390, 844),
          );

      testWidgets('tudo o que é clicável tem rótulo', (tester) async {
        final semantica = tester.ensureSemantics();
        await montar(tester);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      });

      testWidgets('o texto tem contraste suficiente (WCAG AA)', (tester) async {
        final semantica = tester.ensureSemantics();
        await montar(tester);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    });
  }
}
