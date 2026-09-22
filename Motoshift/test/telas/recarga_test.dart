// O fluxo de recarga, em dois tempos.
//
// O que precisa ficar preso aqui não é a aparência da tela: é que criar a
// cobrança NÃO credita nada. O crédito só acontece na confirmação, que no
// mundo real é o webhook do provedor. Se a tela um dia passar a creditar no
// primeiro passo, o app estaria mostrando saldo que o banco não confirmou.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/cobranca.dart';
import 'package:moto_shift/views/recarga/recarga_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  Future<FakeCarteiraApi> abrirRecarga(
    WidgetTester tester, {
    double? valorSugerido,
  }) async {
    final api = FakeApiService();
    await pumpGolden(
      tester,
      child: RecargaScreen(valorSugerido: valorSugerido),
      apiFake: api,
    );
    return api.carteira as FakeCarteiraApi;
  }

  testWidgets('abre pedindo o valor, sem cobrança nenhuma criada',
      (tester) async {
    final carteira = await abrirRecarga(tester);

    expect(find.text('Quanto você quer adicionar?'), findsOneWidget);
    expect(find.byKey(const Key('recarga-valor')), findsOneWidget);
    expect(carteira.recargasCriadas, isEmpty);
    // O código Pix só existe depois de a cobrança ser aberta.
    expect(find.byKey(const Key('recarga-codigo')), findsNothing);
  });

  testWidgets('o botão de gerar só habilita com um valor válido',
      (tester) async {
    await abrirRecarga(tester);

    final botao = find.byKey(const Key('recarga-gerar'));
    expect(tester.widget<FilledButton>(botao).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('recarga-valor')), '150,00');
    await tester.pump();

    expect(tester.widget<FilledButton>(botao).onPressed, isNotNull);
  });

  testWidgets('os atalhos preenchem o valor', (tester) async {
    await abrirRecarga(tester);

    await tester.tap(find.byKey(const Key('recarga-atalho-200')));
    await tester.pump();

    expect(find.text('200,00'), findsOneWidget);
  });

  testWidgets('gerar a cobrança mostra o Pix e NÃO credita nada',
      (tester) async {
    final carteira = await abrirRecarga(tester);

    await tester.enterText(find.byKey(const Key('recarga-valor')), '150,00');
    await tester.pump();
    await tester.tap(find.byKey(const Key('recarga-gerar')));
    await tester.pumpAndSettle();

    expect(carteira.recargasCriadas, hasLength(1));
    expect(carteira.recargasCriadas.single.valor, 150);
    expect(carteira.recargasCriadas.single.status, StatusCobranca.pendente);

    // Nenhuma confirmação ainda: o dinheiro não entrou.
    expect(carteira.confirmacoes, isEmpty);

    expect(find.byKey(const Key('recarga-qr')), findsOneWidget);
    expect(find.byKey(const Key('recarga-codigo')), findsOneWidget);
    expect(find.text('Pague R\$ 150,00'), findsOneWidget);
    // A tela diz que o gateway é simulado, em vez de fingir um Pix real.
    expect(find.textContaining('gateway simulado'), findsOneWidget);
  });

  testWidgets('simular o pagamento confirma a cobrança criada',
      (tester) async {
    final carteira = await abrirRecarga(tester);

    await tester.enterText(find.byKey(const Key('recarga-valor')), '150,00');
    await tester.pump();
    await tester.tap(find.byKey(const Key('recarga-gerar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recarga-simular')));
    await tester.pumpAndSettle();

    // Confirma exatamente a cobrança que foi aberta — e uma só vez.
    expect(carteira.confirmacoes,
        equals([carteira.recargasCriadas.single.id]));
  });

  testWidgets('aberta a partir de uma publicação sem saldo, sugere o que falta',
      (tester) async {
    await abrirRecarga(tester, valorSugerido: 163.47);

    expect(find.byKey(const Key('recarga-aviso-saldo')), findsOneWidget);
    expect(find.textContaining('Faltam R\$ 163,47'), findsOneWidget);
    // Arredondado para cima em dezenas: ninguém recarrega R$ 163,47.
    expect(find.text('170,00'), findsOneWidget);
  });

  testWidgets('poder voltar e alterar o valor antes de pagar', (tester) async {
    await abrirRecarga(tester);

    await tester.enterText(find.byKey(const Key('recarga-valor')), '150,00');
    await tester.pump();
    await tester.tap(find.byKey(const Key('recarga-gerar')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alterar valor'));
    await tester.pumpAndSettle();

    expect(find.text('Quanto você quer adicionar?'), findsOneWidget);
  });
}
