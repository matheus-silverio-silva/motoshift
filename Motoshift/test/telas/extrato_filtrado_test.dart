// O extrato com filtro: o que a tela manda para a API e o que ela desenha com
// o que volta.
//
// São duas coisas diferentes e as duas importam. O filtro foi movido do cliente
// para o servidor justamente porque filtrar em memória impedia paginar — se a
// tela parasse de enviar o critério e voltasse a esconder linhas por conta
// própria, a lista pareceria certa e a paginação ficaria errada em silêncio.
// Por isso o fake registra o filtro recebido, e o teste confere os dois lados.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/views/extrato/extrato_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  /// Monta o extrato e devolve o fake da carteira, para inspecionar as chamadas.
  Future<FakeCarteiraApi> abrirExtrato(WidgetTester tester) async {
    final api = FakeApiService();
    await pumpGolden(
      tester,
      child: ExtratoScreen(agora: dataAncoraGolden),
      apiFake: api,
    );
    return api.carteira as FakeCarteiraApi;
  }

  testWidgets('abre listando tudo, agrupado por dia', (tester) async {
    final carteira = await abrirExtrato(tester);

    // Sem filtro na primeira carga: a tela não inventa um recorte.
    expect(carteira.filtrosRecebidos, hasLength(1));
    expect(carteira.filtrosRecebidos.single.vazio, isTrue);

    expect(find.text('Recarga via Pix'), findsOneWidget);
    expect(find.text('Transferência Pix — ricardo@pix.com'), findsOneWidget);
    expect(find.byKey(const Key('extrato-total')), findsOneWidget);
  });

  testWidgets('o sinal de cada linha vem da natureza, não do tipo',
      (tester) async {
    await abrirExtrato(tester);

    // Crédito com '+', débito com '−' (menos tipográfico).
    expect(find.text('+R\$ 500,00'), findsOneWidget);
    expect(find.text('−R\$ 200,00'), findsOneWidget);

    // O lançamento sem natureza — linha anterior à V12 — aparece sem sinal,
    // em vez de ser chutado para o lado do crédito.
    expect(find.text('R\$ 45,00'), findsOneWidget);
    expect(find.text('+R\$ 45,00'), findsNothing);
  });

  testWidgets('filtrar por saída manda o critério para a API e reduz a lista',
      (tester) async {
    final carteira = await abrirExtrato(tester);

    await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filtro-natureza-debito')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-aplicar')));
    await tester.pumpAndSettle();

    // O filtro chegou à API...
    expect(carteira.filtrosRecebidos.last.natureza, NaturezaTransacao.debito);
    expect(carteira.filtrosRecebidos.last.parametros['natureza'], 'debito');

    // ...e a tela desenhou só o que voltou.
    expect(find.text('Transferência Pix — ricardo@pix.com'), findsOneWidget);
    expect(find.text('Recarga via Pix'), findsNothing);
  });

  testWidgets('filtrar por tipo envia o valor que a API entende',
      (tester) async {
    final carteira = await abrirExtrato(tester);

    await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-tipo-pagamentoRecebido')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-aplicar')));
    await tester.pumpAndSettle();

    // snake_case, e não o nome do enum em Dart: é o contrato do backend.
    expect(carteira.filtrosRecebidos.last.parametros['tipos'],
        'pagamento_recebido');
    expect(find.text('Turno finalizado: Hamburgueria da Cláudia'),
        findsOneWidget);
    expect(find.text('Recarga via Pix'), findsNothing);
  });

  testWidgets('busca textual vai junto do filtro', (tester) async {
    final carteira = await abrirExtrato(tester);

    await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
    await tester.pumpAndSettle();
    // A busca e a ultima secao da folha: traze-la para a viewport antes de
    // digitar. scrollUntilVisible nao serve — ha dois Scrollables na arvore
    // (a lista do extrato e a propria folha) e ele nao sabe qual rolar; e
    // ensureVisible tambem nao, porque a SliverList so constroi o que esta na
    // viewport — o campo nem existe na arvore antes de rolar ate ele.
    await tester.dragUntilVisible(
      find.byKey(const Key('filtro-busca')),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('filtro-busca')), 'recarga');
    await tester.tap(find.byKey(const Key('filtro-aplicar')));
    await tester.pumpAndSettle();

    expect(carteira.filtrosRecebidos.last.busca, 'recarga');
    expect(find.text('Recarga via Pix'), findsOneWidget);
    expect(find.text('Transferência Pix — ricardo@pix.com'), findsNothing);
  });

  testWidgets('filtro que não casa com nada mostra o vazio certo',
      (tester) async {
    await abrirExtrato(tester);

    await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('filtro-busca')),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('filtro-busca')), 'inexistente');
    await tester.tap(find.byKey(const Key('filtro-aplicar')));
    await tester.pumpAndSettle();

    // A mensagem distingue "você não tem lançamentos" de "seu filtro não
    // achou nada" — a segunda tem conserto, a primeira não.
    expect(find.text('Nenhum lançamento com esses filtros.'), findsOneWidget);
  });

  testWidgets('limpar filtros volta a listar tudo', (tester) async {
    final carteira = await abrirExtrato(tester);

    await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-natureza-debito')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-aplicar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('extrato-limpar-filtros')));
    await tester.pumpAndSettle();

    expect(carteira.filtrosRecebidos.last.vazio, isTrue);
    expect(find.text('Recarga via Pix'), findsOneWidget);
  });

  testWidgets('exportar usa os mesmos filtros da tela e entrega o conteúdo',
      (tester) async {
    fingirAreaDeTransferencia(tester);
    await abrirExtrato(tester);

    await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-natureza-credito')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtro-aplicar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('extrato-exportar')));
    await tester.pumpAndSettle();

    // O botão baixava o CSV e dizia "N exportados" sem entregar nada: o
    // conteúdo morria na memória do app. Agora o aviso diz onde ele está.
    expect(find.textContaining('Cole numa planilha'), findsOneWidget);
    expect(find.textContaining('extrato.csv'), findsOneWidget);
  });
}
