import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/financeiro_api.dart';
import 'package:moto_shift/utils/formato_fiscal.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/resultado/lancamento_form.dart';
import 'package:moto_shift/widgets/situacao_do_resultado.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navegacao/app_de_teste.dart';
import '../test_helpers.dart';

/// O painel depois da revisão de 07/10 (SCRUM-49): o cartão "Resultado do
/// mês" e os números com a formatação do resto do app.
///
/// O painel mostrava "R$ 1850", "R$ 320" e "4.70", e para saber se o mês dava
/// lucro era preciso abrir o menu e achar a tela de resultado.
void main() {
  setUpAll(setupGoldenTests);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final cartao = find.byKey(const Key('painel-resultado-do-mes'));
  final texto = find.byKey(const Key('painel-resultado-texto'));

  Widget painelDo(TipoUsuario papel) => papel == TipoUsuario.lojista
      ? DashboardLojistScreen(agora: dataAncoraGolden)
      : DashboardMotoboyScreen(agora: dataAncoraGolden);

  Future<FakeFinanceiroApi> montar(
    WidgetTester tester, {
    TipoUsuario papel = TipoUsuario.motoboy,
    bool comPrejuizo = false,
    bool semLancamentos = false,
    ApiException? erroNaDre,
    Size viewport = const Size(390, 1600),
  }) async {
    final financeiro = FakeFinanceiroApi(
      papel: papel,
      comPrejuizo: comPrejuizo,
      semLancamentos: semLancamentos,
      erroNaDre: erroNaDre,
    );
    await pumpGolden(
      tester,
      child: painelDo(papel),
      tipoUsuario: papel,
      apiFake: _Api(papel, financeiro),
      viewport: viewport,
    );
    return financeiro;
  }

  group('cartão "Resultado do mês"', () {
    for (final papel in TipoUsuario.values) {
      testWidgets('${papel.name}: diz a situação por extenso, com o selo da tela de resultado',
          (tester) async {
        final api = await montar(tester, papel: papel);

        expect(cartao, findsOneWidget);
        expect(find.text('RESULTADO DO MÊS'), findsOneWidget);
        expect(
            tester.widget<Text>(texto).data,
            papel == TipoUsuario.lojista
                ? 'Lucro de ${FormatoFiscal.moeda(197)}'
                : 'Lucro de ${FormatoFiscal.moeda(111.95)}');
        // O ícone com o rótulo, e não só a cor.
        expect(
            find.descendant(of: cartao, matching: find.byType(SeloDeSituacao)), findsOneWidget);
        expect(find.descendant(of: cartao, matching: find.text('Lucro')), findsOneWidget);
        expect(find.descendant(of: cartao, matching: find.byIcon(Icons.trending_up_rounded)),
            findsOneWidget);
        // A DRE pedida é a do mês corrente, até hoje.
        expect(api.periodosPedidos.single, (DateTime(2026, 8, 1), dataAncoraGolden));
      });
    }

    testWidgets('prejuízo: "Prejuízo de R\$ 308,05" — o valor sem sinal, a palavra dizendo',
        (tester) async {
      await montar(tester, comPrejuizo: true);

      expect(tester.widget<Text>(texto).data, 'Prejuízo de ${FormatoFiscal.moeda(308.05)}');
      expect(find.descendant(of: cartao, matching: find.text('Prejuízo')), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.byIcon(Icons.trending_down_rounded)),
          findsOneWidget);
    });

    testWidgets('o leitor de tela ouve o cartão como um botão só, com a situação', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);

      final no = find.bySemanticsLabel(RegExp(r'^Resultado do mês\. Lucro de R\$\s111,95\. '));
      expect(no, findsOneWidget);
      expect(tester.getSemantics(no), isSemantics(isButton: true, hasTapAction: true));
      semantica.dispose();
    });

    testWidgets('sem lançamento manual no mês: convida a informar os custos, sem mostrar um lucro que não é',
        (tester) async {
      await montar(tester, semLancamentos: true);

      expect(tester.widget<Text>(texto).data, 'Informe seus custos para ver o lucro real');
      expect(find.descendant(of: cartao, matching: find.textContaining('Lucro de')), findsNothing);
      expect(find.descendant(of: cartao, matching: find.byType(SeloDeSituacao)), findsNothing);
    });

    testWidgets('sem lançamento manual, o toque abre o formulário; salvar recarrega o painel',
        (tester) async {
      final api = await montar(tester, semLancamentos: true);
      final cargas = api.periodosPedidos.length;

      await tester.tap(cartao);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FormularioDeLancamento), findsOneWidget);
      expect(find.text('Novo lançamento'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lancamento-categoria')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.textContaining('Combustível').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '1.500');
      await tester.ensureVisible(find.byKey(const Key('lancamento-salvar')));
      await tester.tap(find.byKey(const Key('lancamento-salvar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.criados.single.valor, 1500.0);
      expect(find.text('Lançamento salvo.'), findsOneWidget);
      expect(api.periodosPedidos, hasLength(cargas + 1));
    });

    testWidgets('lojista sem lançamento: o convite fala das taxas de entrega', (tester) async {
      await montar(tester, papel: TipoUsuario.lojista, semLancamentos: true);

      expect(tester.widget<Text>(texto).data, 'Informe as taxas de entrega para ver o lucro real');
    });

    for (final papel in TipoUsuario.values) {
      testWidgets('${papel.name}: se a DRE falha, o cartão some e o painel continua inteiro',
          (tester) async {
        await montar(tester,
            papel: papel, erroNaDre: const ApiException(500, 'Erro interno, tente novamente'));

        expect(cartao, findsNothing);
        expect(
            find.text(papel == TipoUsuario.lojista ? 'GASTO TOTAL' : 'GANHOS MÊS'), findsOneWidget);
        expect(find.textContaining('Erro interno'), findsNothing);
      });
    }

    for (final papel in TipoUsuario.values) {
      for (final largura in [celular, desktop]) {
        testWidgets('${papel.name}, ${nomeDaLargura(largura)}: tocar no cartão abre a tela de resultado',
            (tester) async {
          final app = await montarApp(
            tester,
            papel: papel,
            largura: largura,
            rota: papel == TipoUsuario.lojista
                ? AppRoutes.dashboardLojista
                : AppRoutes.dashboardMotoboy,
          );
          expect(cartao, findsOneWidget);

          await tester.ensureVisible(cartao);
          await tester.tap(cartao);
          await assentar(tester);

          expect(app.paginas.last, AppRoutes.resultado);
        });
      }
    }
  });

  group('formatação do painel', () {
    testWidgets('entregador: dinheiro pelo formatador do app, score com vírgula e sem "+ este mês"',
        (tester) async {
      await montar(tester);

      expect(find.text(FormatoFiscal.moeda(1850)), findsOneWidget);
      expect(find.text(FormatoFiscal.moeda(320)), findsOneWidget);
      expect(find.text('4,70'), findsOneWidget);
      expect(find.text('turnos e gorjetas'), findsOneWidget);

      expect(find.text('R\$ 1850'), findsNothing);
      expect(find.text('R\$ 320'), findsNothing);
      expect(find.text('4.70'), findsNothing);
      expect(find.text('+ este mês'), findsNothing);
      // Nem nos cartões de turno: nenhum "R$ 120" sem centavos no painel.
      expect(find.textContaining(RegExp(r'^R\$\s?\d+$')), findsNothing);
    });

    testWidgets('lojista: gasto total com milhar e centavos, avaliação com vírgula', (tester) async {
      await montar(tester, papel: TipoUsuario.lojista);

      expect(find.text(FormatoFiscal.moeda(1500)), findsOneWidget);
      expect(find.text('4,8'), findsOneWidget);
      expect(find.text('R\$ 1500'), findsNothing);
      expect(find.text('4.8'), findsNothing);
      expect(find.textContaining(RegExp(r'^R\$\s?\d+$')), findsNothing);
    });

    testWidgets('entregador no desktop: os mesmos números, com o rótulo que diz o que é o ganho',
        (tester) async {
      await montar(tester, viewport: const Size(1440, 1200));

      expect(find.text(FormatoFiscal.moeda(1850)), findsOneWidget);
      expect(find.text(FormatoFiscal.moeda(320)), findsOneWidget);
      expect(find.text('4,70'), findsOneWidget);
      expect(find.text('turnos e gorjetas recebidos'), findsOneWidget);
      expect(find.text('acumulado na carteira'), findsNothing);
    });
  });
}

/// O fake da API com o financeiro que o teste escolhe.
class _Api extends FakeApiService {
  _Api(TipoUsuario papel, this._financeiroDoTeste) : super(tipoUsuario: papel);

  final FakeFinanceiroApi _financeiroDoTeste;

  @override
  FinanceiroApi get financeiro => _financeiroDoTeste;
}
