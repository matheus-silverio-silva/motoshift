// Percorre o menu inteiro, por papel e por largura, clicando de verdade.
//
// O menu_completo_test verifica o NavConfig como dado — toda rota está em
// algum menu, a barra inferior tem quatro itens. Este aqui verifica o que a
// pessoa vive: sai do início, abre o menu, toca em cada item e confere três
// coisas em cada parada:
//
//   1. chegou na rota do item (e não na de outro papel, como a Agenda levava
//      o entregador ao início do lojista);
//   2. a pilha tem UMA página — item de menu troca de seção, não empilha;
//   3. o item destacado no menu é o da tela em que a pessoa está.
//
// No celular o menu é a gaveta aberta pelo header; no desktop, a barra
// lateral fixa. Como cada parada abre o menu a partir da tela anterior, o
// passeio também prova que toda seção tem menu — uma tela sem saída
// interrompe o teste ali.

import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/routes/nav_config.dart';
import 'package:moto_shift/widgets/app_bottom_nav.dart';
import 'package:moto_shift/widgets/app_nav_drawer.dart';
import 'package:moto_shift/widgets/desktop/app_sidebar.dart';

import '../test_helpers.dart';
import 'app_de_teste.dart';

void main() {
  setUpAll(setupGoldenTests);

  for (final papel in TipoUsuario.values) {
    for (final largura in [celular, desktop]) {
      testWidgets(
          '${papel.name} em ${nomeDaLargura(largura)}: todo item do menu '
          'troca de seção e fica destacado', (tester) async {
        final app = await montarApp(
          tester,
          papel: papel,
          largura: largura,
          rota: NavConfig.raizDe(papel),
        );
        final ehCelular = largura == celular;

        for (final item in NavConfig.itens(papel)) {
          if (ehCelular) {
            await tocar(tester, find.bySemanticsLabel('Abrir menu'));
            expect(find.byType(AppNavDrawer), findsOneWidget,
                reason: 'a tela anterior a "${item.label}" não tem menu');
          }

          final menu = ehCelular
              ? find.byType(AppNavDrawer)
              : find.byType(AppSidebar);
          await tocar(
            tester,
            find.descendant(of: menu, matching: find.text(item.label)).first,
          );

          expect(app.paginas, [item.route],
              reason: '"${item.label}" deveria trocar a pilha inteira pela '
                  'rota ${item.route}');
          expect(tester.takeException(), isNull,
              reason: 'a tela de "${item.label}" lançou exceção ao abrir');

          if (!ehCelular) {
            final lateral = tester.widget<AppSidebar>(find.byType(AppSidebar));
            expect(lateral.selectedRoute, item.route,
                reason: 'no desktop, "${item.label}" precisa ficar destacado');
          } else if (item.naBarraInferior) {
            final barra =
                tester.widget<AppBottomNav>(find.byType(AppBottomNav));
            expect(NavConfig.secaoDe(barra.rotaAtual), item.route,
                reason: 'na barra inferior, "${item.label}" precisa ficar '
                    'destacado');
          }
        }
      });
    }
  }

  // O extrato completo existia, com filtros e exportação, sem nenhum botão
  // até ele. Agora é sub-página da seção de dinheiro de cada papel: empilha
  // sobre ela, e o menu continua destacando a seção.
  for (final papel in TipoUsuario.values) {
    for (final largura in [celular, desktop]) {
      testWidgets(
          '${papel.name} em ${nomeDaLargura(largura)}: extrato completo é '
          'sub-página da seção de dinheiro', (tester) async {
        final secao = papel == TipoUsuario.lojista
            ? AppRoutes.saldoLojista
            : AppRoutes.carteira;
        final app = await montarApp(
          tester,
          papel: papel,
          largura: largura,
          rota: secao,
        );

        final botao = papel == TipoUsuario.lojista
            ? find.byKey(const Key('saldo-lojista-extrato'))
            : largura == desktop
                ? find.byKey(const Key('carteira-extrato-completo'))
                : find.text('Ver completo');
        await tocar(tester, botao);

        expect(app.paginas, [secao, AppRoutes.extrato]);
        if (largura == desktop) {
          final lateral = tester.widget<AppSidebar>(find.byType(AppSidebar));
          expect(lateral.selectedRoute, NavConfig.secaoDe(AppRoutes.extrato));
        }
      });
    }
  }
}
