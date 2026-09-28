// Exportar em PDF: extrato, relatório financeiro e informe anual.
//
// O que estes testes prendem, e que nenhuma captura de tela mostra: que o PDF
// é gerado, que traz os MESMOS números da tela, e que o conteúdo segue o papel
// — o PDF do entregador não tem coluna de lojista (bloqueado), nem o do
// lojista número de entregador (a receber). E que o informe, que imita um
// documento fiscal, sai com a marca de simulação.
//
// O PDF é gerado sem compressão para o texto poder ser lido de volta — ver
// [textoDoPdf]. É o mesmo documento, só sem o zip do conteúdo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/extrato_filtro.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/carteira_api.dart';
import 'package:moto_shift/services/relatorio_pdf.dart';
import 'package:moto_shift/views/extrato/extrato_screen.dart';
import 'package:moto_shift/views/relatorios_financeiros/relatorios_financeiros_screen.dart';

import '../test_helpers.dart';
import 'texto_do_pdf.dart';

const _entregador = TitularDoPdf(nome: 'Ricardo Souza', papel: TipoUsuario.motoboy);
const _lojista = TitularDoPdf(nome: 'Cláudia Oliveira', papel: TipoUsuario.lojista);

void main() {
  setUpAll(setupGoldenTests);

  final geradoEm = DateTime(2026, 9, 28, 10, 30);

  group('PDF do extrato', () {
    test('é gerado com cabeçalho, filtro aplicado, totais e a tabela', () async {
      final bytes = await RelatorioPdf.extrato(
        titular: _entregador,
        filtro: const ExtratoFiltro(tipos: {TipoTransacao.pagamentoRecebido}),
        lancamentos: fakeExtrato(),
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(texto, contains('EXTRATO DA CARTEIRA'));
      expect(texto, contains('Ricardo Souza'));
      expect(texto, contains('Entregador — prestador de serviço'));
      expect(texto, contains('pagamento recebido'), reason: 'o filtro aplicado');
      // Os totais do que está listado: recarga de 500 e pagamento de 120.
      expect(texto, contains('Lançamentos'));
      expect(texto, contains('500,00'));
      expect(texto, contains('120,00'));
      // O entregador não tem saldo bloqueado: a coluna não existe para ele.
      expect(texto, contains('Saldo após'));
      expect(texto, isNot(contains('Bloqueado após')));
    });

    test('o do lojista tem a coluna do bloqueado', () async {
      final bytes = await RelatorioPdf.extrato(
        titular: _lojista,
        filtro: const ExtratoFiltro(),
        lancamentos: fakeExtrato(),
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(texto, contains('Lojista — contratante do serviço'));
      expect(texto, contains('Bloqueado após'));
      expect(texto, contains('nenhum'), reason: 'sem filtro, o PDF diz que não há');
    });
  });

  group('PDF do relatório', () {
    test('entregador: os cartões dele, com os valores da tela', () async {
      final bytes = await RelatorioPdf.relatorio(
        titular: _entregador,
        de: DateTime(2026, 8, 30),
        ate: DateTime(2026, 9, 28),
        resumo: fakeResumoFinanceiro(),
        fluxo: fakeFluxo(),
        lancamentos: fakeExtrato(),
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(texto, contains('RELATÓRIO FINANCEIRO'));
      expect(texto, contains('30/08/2026 a 28/09/2026'));
      expect(texto, contains('Recebido por serviços'));
      expect(texto, contains('620,00'));
      expect(texto, contains('Sacado'));
      expect(texto, contains('A receber'));
      expect(texto, contains('240,00'));
      expect(texto, isNot(contains('Comprometido')));
      expect(texto, isNot(contains('Recarregado')));
    });

    test('lojista: os cartões dele, sem nada de entregador', () async {
      final bytes = await RelatorioPdf.relatorio(
        titular: _lojista,
        de: DateTime(2026, 8, 30),
        ate: DateTime(2026, 9, 28),
        resumo: fakeResumoLojista(),
        fluxo: const [],
        lancamentos: const [],
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(texto, contains('Recarregado'));
      expect(texto, contains('Pago a entregadores'));
      expect(texto, contains('Comprometido em turnos'));
      expect(texto, contains('360,00'));
      expect(texto, isNot(contains('A receber')));
      expect(texto, isNot(contains('Recebido por serviços')));
      expect(texto, contains('Nenhum lançamento neste recorte'));
    });
  });

  group('PDF do informe anual', () {
    test('leva a marca de simulação, os totais e as fontes pagadoras', () async {
      final bytes = await RelatorioPdf.informe(
        titular: _entregador,
        informe: fakeInformeAnual(ano: 2026),
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(texto, contains('DOCUMENTO SIMULADO — SEM VALOR FISCAL'));
      expect(texto, contains('INFORME DE RENDIMENTOS'));
      expect(texto, contains('Ano-calendário: 2026'));
      expect(texto, contains('1.200,00'));
      expect(texto, contains('POR FONTE PAGADORA'));
      expect(texto, contains('Hamburgueria da Cláudia'));
      expect(texto, contains('Sem nota fiscal'));
    });

    test('o do lojista fala de prestadores', () async {
      final bytes = await RelatorioPdf.informe(
        titular: _lojista,
        informe: fakeInformeAnual(ano: 2026, papel: 'tomador'),
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(texto, contains('POR PRESTADOR'));
      expect(texto, contains('Total de serviços tomados'));
      expect(texto, isNot(contains('POR FONTE PAGADORA')));
    });
  });

  group('Pela tela', () {
    testWidgets('extrato: "Exportar" pergunta o formato, e o PDF leva o filtro da tela',
        (tester) async {
      final impressora = fingirImpressora(tester);
      final api = _Api();

      await pumpGolden(tester,
          apiFake: api, child: ExtratoScreen(agora: dataAncoraGolden));
      await tester.tap(find.byKey(const Key('extrato-exportar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exportar-planilha')), findsOneWidget);
      expect(find.byKey(const Key('exportar-pdf')), findsOneWidget);

      await tester.tap(find.byKey(const Key('exportar-pdf')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();

      expect(api.carteiraFake.exportacoesEmLista, hasLength(1));
      expect(impressora.nome, startsWith('extrato-'));
      expect(String.fromCharCodes(impressora.bytes!.take(4)), '%PDF');
    });

    testWidgets('relatórios: o PDF sai com o período da tela', (tester) async {
      final impressora = fingirImpressora(tester);
      final api = _Api();

      await pumpGolden(tester,
          apiFake: api,
          child: RelatoriosFinanceirosScreen(agora: dataAncoraGolden));
      // O botão fica no fim da lista, que o celular só constrói ao rolar.
      final botao = find.byKey(const Key('relatorio-exportar'));
      // O gráfico de fluxo também rola (na horizontal): a lista é a primeira.
      await tester.scrollUntilVisible(botao, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exportar-pdf')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();

      final filtro = api.carteiraFake.exportacoesEmLista.single;
      expect(filtro.dataInicio, isNotNull);
      expect(filtro.dataFim, isNotNull);
      expect(impressora.nome, startsWith('relatorio-'));
      expect(String.fromCharCodes(impressora.bytes!.take(4)), '%PDF');
    });
  });
}

class _Api extends FakeApiService {
  final FakeCarteiraApi carteiraFake = FakeCarteiraApi();

  @override
  CarteiraApi get carteira => carteiraFake;
}
