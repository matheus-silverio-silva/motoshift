// A tela de notas fiscais com filtros, paginação e informe anual.
//
// O que estes testes prendem, e que nenhuma captura de tela mostra: o filtro
// VAI PARA A API. A tentação é peneirar em memória a lista já baixada — funciona
// na demonstração, com três notas, e deixa de funcionar no segundo ano de uso,
// quando abrir a tela passa a baixar tudo. Por isso as asserções olham o que a
// API recebeu, e não só o que a tela mostrou.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/nota_fiscal.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/nota_fiscal_api.dart';
import 'package:moto_shift/views/notas_fiscais/notas_fiscais_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  group('Filtros', () {
    testWidgets('tocar em "Válidas" manda a situação para a API', (tester) async {
      final api = _api(notas: [fakeNotaFiscal()], total: 1);

      await _abrir(tester, api);
      await tester.tap(find.text('Válidas'));
      await tester.pumpAndSettle();

      expect(api.notasApi.ultimoFiltro?.status, 'emitida');
      // Volta para a primeira página: filtro novo, contagem nova.
      expect(api.notasApi.ultimoTamanho, 20);
      expect(api.notasApi.ultimaPagina, 0);
    });

    for (final papel in TipoUsuario.values) {
      testWidgets('${papel.name}: sem pílula de papel — cada conta tem um lado só',
          (tester) async {
        final api = _api(notas: [fakeNotaFiscal()], total: 1);

        await _abrir(tester, api, tipoUsuario: papel);

        expect(find.text('Prestei'), findsNothing);
        expect(find.text('Tomei'), findsNothing);
        expect(api.notasApi.ultimoFiltro?.papel, isNull);
      });
    }

    testWidgets('a pílula de situação liga e desliga no mesmo toque',
        (tester) async {
      final api = _api(notas: [fakeNotaFiscal()], total: 1);

      await _abrir(tester, api);
      await _tocarNoChip(tester, 'Canceladas');
      expect(api.notasApi.ultimoFiltro?.status, 'cancelada');

      await _tocarNoChip(tester, 'Canceladas');
      expect(api.notasApi.ultimoFiltro?.status, isNull);
    });

    testWidgets('a contraparte sai das notas à vista e vai para o filtro',
        (tester) async {
      final api = _api(notas: [fakeNotaFiscal()], total: 1);

      await _abrir(tester, api);
      final chip = find.byKey(const Key('notas-filtro-contraparte'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // A nota falsa é uma prestação: a contraparte é a tomadora.
      await tester.tap(find.text('Hamburgueria da Cláudia').last);
      await tester.pumpAndSettle();

      expect(api.notasApi.ultimoFiltro?.contraparteId, 2);
    });

    testWidgets('lista vazia com filtro diz que é o filtro, e não a falta de notas',
        (tester) async {
      final api = _api(notas: [fakeNotaFiscal()], total: 1);

      await _abrir(tester, api);
      api.notasApi.notas = const [];
      api.notasApi.total = 0;

      await _tocarNoChip(tester, 'Canceladas');

      expect(find.textContaining('filtrando só as canceladas'), findsOneWidget);
    });
  });

  group('Paginação', () {
    testWidgets('com mais notas do que vieram, oferece carregar mais do mesmo filtro',
        (tester) async {
      // Duas notas de sete: o resto continua no servidor.
      final api = _api(notas: [fakeNotaFiscal(), _outra()], total: 7);

      await _abrir(tester, api);
      expect(find.textContaining('5 restantes'), findsOneWidget);

      await tester.tap(find.text('Válidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notas-carregar-mais')));
      await tester.pumpAndSettle();

      expect(api.notasApi.ultimoTamanho, 40);
      // O filtro sobrevive à paginação — senão "carregar mais" viraria
      // "carregar tudo de novo".
      expect(api.notasApi.ultimoFiltro?.status, 'emitida');
    });

    testWidgets('sem mais nada para buscar, não mostra o botão', (tester) async {
      final api = _api(notas: [fakeNotaFiscal()], total: 1);

      await _abrir(tester, api);

      expect(find.byKey(const Key('notas-carregar-mais')), findsNothing);
      expect(find.text('1 nota no total'), findsOneWidget);
    });
  });

  group('Informe anual', () {
    testWidgets('mostra o total do ano, as contrapartes e os meses',
        (tester) async {
      final api = _api(notas: [fakeNotaFiscal()], total: 1);

      await _abrir(tester, api);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();

      expect(api.notasApi.anoPedidoNoResumo, DateTime.now().year);
      expect(find.textContaining('1.200,00'), findsOneWidget);
      expect(find.textContaining('Informe de rendimentos ·'), findsOneWidget);
      // O total vem do extrato: um pagamento ainda sem nota continua contado,
      // e a tela diz quantos são.
      expect(find.textContaining('6 pagamento(s) · 5 com nota · 1 sem nota'),
          findsOneWidget);
      expect(find.text('Pizzaria do Bairro'), findsOneWidget);
      expect(find.text('POR FONTE PAGADORA'), findsOneWidget);
      // Os doze meses, inclusive os zerados.
      expect(find.text('ago'), findsOneWidget);
      expect(find.text('fev'), findsOneWidget);
    });

    testWidgets('sem retenção na fonte, a linha de retenção não aparece',
        (tester) async {
      final api = _api(notas: const [], total: 0);

      await _abrir(tester, api);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('informe-retencao')), findsNothing);
    });

    testWidgets('com retenção, o informe mostra ISS e IRRF retidos',
        (tester) async {
      final api = _api(notas: const [], total: 0);
      api.notasApi.informe = fakeInformeAnual(retido: true);

      await _abrir(tester, api);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('informe-retencao')), findsOneWidget);
      expect(find.textContaining('ISS'), findsWidgets);
    });

    testWidgets('trocar o ano pede o informe daquele ano', (tester) async {
      final api = _api(notas: const [], total: 0);
      final anterior = DateTime.now().year - 1;

      await _abrir(tester, api);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$anterior'));
      await tester.pumpAndSettle();

      expect(api.notasApi.anoPedidoNoResumo, anterior);
    });

    testWidgets('o informe do lojista fala de prestadores, não de fontes pagadoras',
        (tester) async {
      final api = _api(notas: const [], total: 0);
      api.notasApi.informe = fakeInformeAnual(papel: 'tomador');

      await _abrir(tester, api, tipoUsuario: TipoUsuario.lojista);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();

      expect(find.text('POR PRESTADOR'), findsOneWidget);
      expect(find.text('POR FONTE PAGADORA'), findsNothing);
    });

    testWidgets('exportar entrega o CSV, em vez de só dizer que exportou',
        (tester) async {
      final api = _api(notas: const [], total: 0);

      final baixados = fingirDownload();
      await _abrir(tester, api);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();
      final botao = find.byKey(const Key('informe-exportar'));
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exportar-planilha')));
      await tester.pumpAndSettle();

      expect(api.notasApi.exportacoesDoResumo, 1);
      // Um arquivo de verdade — ver entregarCsv.
      expect(baixados.single.nome, startsWith('informe-'));
      expect(baixados.single.nome, endsWith('.csv'));
    });

    testWidgets('exportar em PDF monta o informe no app e o entrega',
        (tester) async {
      final api = _api(notas: const [], total: 0);
      final impressora = fingirImpressora(tester);

      await _abrir(tester, api);
      await tester.tap(find.text('Informe anual'));
      await tester.pumpAndSettle();
      final botao = find.byKey(const Key('informe-exportar'));
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exportar-pdf')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();

      // O PDF sai do informe que a tela já tem — o CSV do backend não é pedido.
      expect(api.notasApi.exportacoesDoResumo, 0);
      expect(impressora.nome, 'informe-${DateTime.now().year}-simulado.pdf');
      expect(String.fromCharCodes(impressora.bytes!.take(4)), '%PDF');
    });
  });
}

/// A barra de filtros rola na horizontal: num celular de 390px as últimas
/// pílulas nascem fora da tela, e tocar sem trazê-las para dentro erra o alvo.
Future<void> _tocarNoChip(WidgetTester tester, String rotulo) async {
  final chip = find.text(rotulo);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _abrir(
  WidgetTester tester,
  _ApiComNotas api, {
  TipoUsuario tipoUsuario = TipoUsuario.motoboy,
}) async {
  await pumpGolden(
    tester,
    child: const NotasFiscaisScreen(),
    tipoUsuario: tipoUsuario,
    apiFake: api,
  );
}

_ApiComNotas _api({required List<NotaFiscal> notas, required int total}) {
  final fake = FakeNotaFiscalApi()
    ..notas = notas
    ..total = total;
  return _ApiComNotas(fake);
}

/// Uma segunda nota, só para a lista ter duas linhas na paginação.
NotaFiscal _outra() {
  final base = fakeNotaFiscal();
  return NotaFiscal(
    id: 78,
    turnoId: 203,
    numero: 13,
    serie: base.serie,
    codigoVerificacao: 'E5F6-G7H8',
    prestadorId: base.prestadorId,
    prestadorNome: base.prestadorNome,
    prestadorDocumentoTipo: base.prestadorDocumentoTipo,
    tomadorId: base.tomadorId,
    tomadorNome: base.tomadorNome,
    tomadorDocumentoTipo: base.tomadorDocumentoTipo,
    tomadorDocumento: base.tomadorDocumento,
    descricaoServico: base.descricaoServico,
    competencia: DateTime(2025, 9, 2, 18),
    valorServico: 150,
    issAliquota: base.issAliquota,
    issValor: 7.5,
    irrfAliquota: base.irrfAliquota,
    irrfValor: 2.25,
    totalTributos: 9.75,
    valorLiquido: 150,
    emitidaEm: DateTime(2025, 9, 3, 9),
    papel: 'prestador',
  );
}

/// O [FakeApiService] com o fake de notas exposto, para o teste ler o que a
/// tela pediu.
class _ApiComNotas extends FakeApiService {
  _ApiComNotas(this.notasApi);

  final FakeNotaFiscalApi notasApi;

  @override
  NotaFiscalApi get notasFiscais => notasApi;
}
