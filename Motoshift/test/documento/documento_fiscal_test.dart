// O documento fiscal no app: o que a tela mostra, o que o PDF leva junto e
// por onde se chega até ele.
//
// A regra que estes testes prendem, e que nenhuma captura de tela mostra: a
// marca de simulação está SEMPRE visível, o documento das partes nunca sai
// inteiro, e as duas políticas de tributo dizem coisas diferentes — com
// retenção, o líquido é menor; sem ela, o líquido é o valor do serviço, que é
// o que o extrato creditou.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/documento_pdf.dart';
import 'package:moto_shift/views/documento_fiscal/documento_fiscal_screen.dart';
import 'package:moto_shift/views/extrato/lancamento_detalhe_screen.dart';
import 'package:moto_shift/views/extrato/lancamento_tile.dart';
import 'package:moto_shift/widgets/documento/comprovante_view.dart';
import 'package:moto_shift/widgets/documento/nfse_view.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  group('NFS-e na tela', () {
    testWidgets('mostra a marca de simulação, as partes e o documento mascarado',
        (tester) async {
      await pumpGolden(tester, child: _tela(NfseView(nota: fakeNotaFiscal())));

      expect(find.byKey(const Key('marca-simulacao')), findsOneWidget);
      expect(find.text('DOCUMENTO SIMULADO — SEM VALOR FISCAL'), findsWidgets);

      expect(find.text('Ricardo Souza'), findsOneWidget);
      expect(find.text('Hamburgueria da Cláudia'), findsOneWidget);
      expect(find.text('CNPJ **.345.678/0001-**'), findsOneWidget);
      // O entregador não tem CPF no cadastro: a tela diz isso, em vez de
      // mostrar a CNH no campo do CPF.
      expect(find.text('CPF não informado no cadastro'), findsOneWidget);

      expect(find.text('Nº 000012 / A1'), findsOneWidget);
      expect(find.text('A1B2-C3D4'), findsOneWidget);
    });

    testWidgets('sem retenção, os tributos são aproximados e o líquido é o valor do serviço',
        (tester) async {
      await pumpGolden(tester, child: _tela(NfseView(nota: fakeNotaFiscal())));

      expect(find.text('Valor aproximado dos tributos (Lei 12.741/2012)'),
          findsOneWidget);
      // `textContaining`, e não `text`: o NumberFormat pt_BR separa "R$" do
      // número com espaço não separável, que não se digita num literal.
      expect(find.textContaining('200,00'), findsNWidgets(2)); // serviço e líquido
      expect(find.textContaining('− '), findsNothing);
    });

    testWidgets('com retenção, o líquido é menor e a nota diz que saiu do pagamento',
        (tester) async {
      await pumpGolden(
          tester, child: _tela(NfseView(nota: fakeNotaFiscal(retidos: true))));

      expect(find.text('Valor aproximado dos tributos (Lei 12.741/2012)'),
          findsNothing);
      expect(find.textContaining('− ').at(0), findsOneWidget);
      expect(find.textContaining('10,00'), findsOneWidget);
      expect(find.textContaining('187,00'), findsOneWidget);
      expect(find.textContaining('retidos na fonte'), findsWidgets);
    });

    testWidgets('nota cancelada avisa que o pagamento continua no extrato',
        (tester) async {
      await pumpGolden(
          tester, child: _tela(NfseView(nota: fakeNotaFiscal(cancelada: true))));

      expect(find.text('Nota cancelada'), findsOneWidget);
      expect(find.textContaining('cancelar a nota não estorna dinheiro'),
          findsOneWidget);
    });
  });

  group('Comprovante na tela', () {
    testWidgets('traz número, código de autenticação e os detalhes do movimento',
        (tester) async {
      await pumpGolden(
          tester, child: _tela(ComprovanteView(comprovante: fakeComprovante())));

      expect(find.byKey(const Key('marca-simulacao')), findsOneWidget);
      expect(find.textContaining('RC-00000091'), findsOneWidget);
      expect(find.text('AAAA-BBBB-CCCC-DDDD'), findsOneWidget);
      expect(find.text('Forma de pagamento'), findsOneWidget);
      expect(find.text('Pagamento confirmado'), findsOneWidget);
      expect(find.text('Recibo de recarga'.toUpperCase()), findsOneWidget);
    });
  });

  group('PDF', () {
    test('gera um PDF de verdade para a nota e para o comprovante', () async {
      for (final doc in [fakeDocumentoNota(retidos: true), fakeDocumentoComprovante()]) {
        final bytes = await DocumentoPdf.gerar(doc);

        // Assinatura do formato e tamanho compatível com uma página que
        // carrega a fonte embutida (subconjunto). Vazio, um PDF tem ~1 KB; se
        // a fonte não tivesse sido carregada, a geração teria estourado no
        // "—" da própria marca de simulação.
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(8000));
      }
    });

    test('o nome do arquivo diz o que é, e que é simulado', () {
      expect(DocumentoPdf.nomeDoArquivo(fakeDocumentoNota()),
          'nfse-000012-simulada.pdf');
      expect(DocumentoPdf.nomeDoArquivo(fakeDocumentoComprovante()),
          'rc-00000091-simulado.pdf');
    });
  });

  group('Por onde se chega ao documento', () {
    testWidgets('o detalhe do lançamento oferece "Gerar nota fiscal" e o selo de emitida',
        (tester) async {
      final pagamento = fakeExtrato().firstWhere((t) => t.id == 92);

      await pumpGolden(tester,
          child: LancamentoDetalheScreen(lancamento: pagamento));

      expect(find.byKey(const Key('selo-nota-emitida')), findsOneWidget);
      // A nota já existe: o botão convida a ver, não a gerar de novo.
      expect(find.text('Ver nota fiscal'), findsOneWidget);
    });

    testWidgets('lançamento sem documento não mostra botão nenhum', (tester) async {
      final reserva = Transacao(
        id: 55,
        motoboyId: 2,
        tipo: TipoTransacao.reserva,
        natureza: NaturezaTransacao.debito,
        valor: 360,
        descricao: 'Reserva do turno: Turno Noite',
        criadoEm: DateTime(2025, 8, 10, 12),
      );

      await pumpGolden(tester, child: LancamentoDetalheScreen(lancamento: reserva));

      expect(find.byKey(const Key('lancamento-gerar-documento')), findsNothing);
      expect(find.byKey(const Key('selo-nota-emitida')), findsNothing);
    });

    testWidgets('a linha do extrato mostra o selo e o atalho do documento',
        (tester) async {
      final pagamento = fakeExtrato().firstWhere((t) => t.id == 92);
      var tocou = false;

      await pumpGolden(
        tester,
        child: _tela(LancamentoTile(
          lancamento: pagamento,
          onDocumento: () => tocou = true,
        )),
      );

      expect(find.byKey(const Key('selo-nota-emitida')), findsOneWidget);
      await tester.tap(find.byKey(const Key('extrato-documento')));
      expect(tocou, isTrue);
    });
  });

  group('Tela do documento', () {
    testWidgets('abre com o documento pronto e oferece baixar e imprimir',
        (tester) async {
      await pumpGolden(
        tester,
        tipoUsuario: TipoUsuario.motoboy,
        child: const DocumentoFiscalScreen(),
        argumentos: DocumentoFiscalArgs(documento: fakeDocumentoNota()),
      );

      expect(find.byType(NfseView), findsOneWidget);
      expect(find.byKey(const Key('documento-baixar-pdf')), findsOneWidget);
      expect(find.byKey(const Key('documento-imprimir')), findsOneWidget);
      expect(find.byKey(const Key('marca-simulacao')), findsOneWidget);
    });

    testWidgets('sem documento pronto, busca pelo lançamento', (tester) async {
      await pumpGolden(
        tester,
        tipoUsuario: TipoUsuario.motoboy,
        child: const DocumentoFiscalScreen(),
        argumentos: const DocumentoFiscalArgs(transacaoId: 91),
      );

      expect(find.byType(ComprovanteView), findsOneWidget);
      expect(find.textContaining('RC-00000091'), findsOneWidget);
    });
  });
}

/// Os widgets de documento são pedaços de tela: o teste os monta num Scaffold
/// rolável, como as telas que os hospedam fazem.
Widget _tela(Widget filho) => Scaffold(
      body: ListView(padding: const EdgeInsets.all(16), children: [filho]),
    );
