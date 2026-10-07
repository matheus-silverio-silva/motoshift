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

import 'package:moto_shift/models/dre.dart';
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

  group('PDF do relatório com a DRE', () {
    test('entregador: a seção "Demonstração do resultado" traz a situação e as linhas', () async {
      final dre = fakeDreEntregador(comPrejuizo: true);
      final bytes = await RelatorioPdf.relatorio(
        titular: _entregador,
        de: DateTime(2026, 8, 1),
        ate: DateTime(2026, 8, 19),
        resumo: fakeResumoFinanceiro(),
        fluxo: fakeFluxo(),
        lancamentos: fakeExtrato(),
        dre: dre,
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(texto, contains('DEMONSTRAÇÃO DO RESULTADO'));
      // A situação por extenso — a mesma frase da tela.
      expect(texto, contains('Prejuízo de'));
      expect(texto, contains('308,05'));
      expect(texto, contains('no período'));
      // As linhas, com o sinal e a origem.
      expect(texto, contains('Pagamentos de turnos'));
      expect(texto, contains('Combustível'));
      expect(texto, contains('Informado por você'));
      expect(texto, contains('Extrato'));
      expect(texto, contains('Margem de contribuição'));
      expect(texto, contains('Resultado do período'));
      expect(texto, contains('420,00'));
      expect(texto, contains('Caixa'));
    });

    test('lojista: a DRE da operação de entrega', () async {
      final bytes = await RelatorioPdf.relatorio(
        titular: _lojista,
        de: DateTime(2026, 8, 1),
        ate: DateTime(2026, 8, 19),
        resumo: fakeResumoLojista(),
        fluxo: const [],
        lancamentos: const [],
        dre: fakeDreLojista(),
        geradoEm: geradoEm,
        comprimir: false,
      );
      final texto = textoDoPdf(bytes);

      expect(texto, contains('DEMONSTRAÇÃO DO RESULTADO'));
      expect(texto, contains('Lucro de'));
      expect(texto, contains('197,00'));
      expect(texto, contains('Receita de entregas'));
      expect(texto, contains('Pagamentos e gorjetas a entregadores'));
      expect(texto, contains('Resultado da operação de entrega'));
      expect(texto, isNot(contains('Combustível')));
    });

    test('sem lançamento informado, o PDF avisa que o resultado ignora o que não passou pela plataforma',
        () async {
      final base = fakeDreEntregador();
      final bytes = await RelatorioPdf.relatorio(
        titular: _entregador,
        de: DateTime(2026, 8, 1),
        ate: DateTime(2026, 8, 19),
        resumo: fakeResumoFinanceiro(),
        fluxo: const [],
        lancamentos: const [],
        dre: Dre(
          papel: base.papel,
          dataInicio: base.dataInicio,
          dataFim: base.dataFim,
          linhas: base.linhas,
          resultado: base.resultado,
          situacao: base.situacao,
        ),
        geradoEm: geradoEm,
        comprimir: false,
      );

      expect(textoDoPdf(bytes), contains('Nenhum custo ou receita foi informado'));
    });

    test('sem DRE, o relatório sai como antes — sem a seção', () async {
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

      expect(textoDoPdf(bytes), isNot(contains('DEMONSTRAÇÃO DO RESULTADO')));
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
