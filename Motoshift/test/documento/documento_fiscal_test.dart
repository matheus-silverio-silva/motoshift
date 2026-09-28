// O documento fiscal no app: o que a tela mostra, o que o PDF leva junto e
// por onde se chega até ele.
//
// A regra que estes testes prendem, e que nenhuma captura de tela mostra: a
// marca de simulação está SEMPRE visível, o documento das partes nunca sai
// inteiro, a NFS-e segue o leiaute oficial do DANFSe (NT SE/CGNFS-e nº
// 008/2026) na tela e no PDF, e as duas políticas de tributo dizem coisas
// diferentes — com retenção, o líquido é menor; sem ela, o líquido é o valor
// do serviço, que é o que o extrato creditou.

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

import '../exportacao/texto_do_pdf.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  group('NFS-e na tela, no leiaute do DANFSe', () {
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

      expect(find.text('A1B2-C3D4'), findsOneWidget);
    });

    testWidgets('traz a identificação do DANFSe: chave de acesso, DPS e QR Code',
        (tester) async {
      await pumpGolden(tester, child: _tela(NfseView(nota: fakeNotaFiscal())));

      expect(find.text('DANFSe v2.0'), findsOneWidget);
      expect(find.text('Documento Auxiliar da NFS-e'), findsOneWidget);
      // 50 dígitos em 10 grupos de 5, abrindo com Curitiba (IBGE 4106902).
      expect(find.text('41069 02210 00000 00000 00000 00000 00001 22508 76973 94438'), findsOneWidget);
      expect(find.text('Número da NFS-e'), findsOneWidget);
      expect(find.text('Número da DPS'), findsOneWidget);
      expect(find.text('Série da DPS'), findsOneWidget);
      expect(find.byKey(const Key('danfse-qrcode')), findsOneWidget);
      expect(find.textContaining('Portal Nacional da NFS-e'), findsOneWidget);
    });

    testWidgets('os quadros vêm na ordem do modelo oficial', (tester) async {
      await pumpGolden(tester, child: _tela(NfseView(nota: fakeNotaFiscal())));

      final ordem = [
        'prestador', 'tomador', 'destinatario', 'intermediario', 'servico',
        'issqn', 'federal', 'ibscbs', 'totais', 'complementares',
      ];
      final alturas = [
        for (final id in ordem)
          tester.getTopLeft(find.byKey(Key('danfse-quadro-$id'))).dy,
      ];
      expect(alturas, orderedEquals([...alturas]..sort()));
      expect(find.text('INTERMEDIÁRIO DO SERVIÇO NÃO IDENTIFICADO NA NFS-e'),
          findsOneWidget);
      expect(find.textContaining('26.01.01 - Serviços de coleta'), findsOneWidget);
      // O lado de quem olha — aqui, o entregador — vem marcado.
      expect(
          find.descendant(
              of: find.byKey(const Key('danfse-quadro-prestador')),
              matching: find.text('você')),
          findsOneWidget);
    });

    testWidgets('sem retenção, o ISSQN não é retido e o líquido é o valor do serviço',
        (tester) async {
      await pumpGolden(tester, child: _tela(NfseView(nota: fakeNotaFiscal())));

      expect(find.text('Não Retido'), findsOneWidget);
      expect(find.text('Valor Líquido da NFS-e'), findsOneWidget);
      // Valor do serviço e BC ISSQN; valor do serviço e líquido nos totais.
      expect(find.text(r'R$ 200,00'), findsNWidgets(4));
      expect(find.text(r'R$ 187,00'), findsNothing);
    });

    testWidgets('com retenção, o líquido é menor e as retenções aparecem nos totais',
        (tester) async {
      await pumpGolden(
          tester, child: _tela(NfseView(nota: fakeNotaFiscal(retidos: true))));

      expect(find.text('Retido pelo Tomador'), findsOneWidget);
      expect(find.text(r'R$ 3,00 (1,50%)'), findsOneWidget);
      expect(find.text(r'R$ 187,00'), findsOneWidget);
    });

    testWidgets('em 2026, IBS e CBS do ano de teste entram e o valor final os soma',
        (tester) async {
      await pumpGolden(
          tester, child: _tela(NfseView(nota: fakeNotaFiscal(anoDeTeste: true))));

      expect(find.text('0,90%'), findsOneWidget); // CBS, LC 214/2025, art. 346
      expect(find.text('0,10%'), findsOneWidget); // IBS UF, art. 343
      expect(find.text(r'R$ 190,00'), findsOneWidget); // base sem o ISSQN
      expect(find.text('Valor Líquido da NFS-e + IBS/CBS'), findsOneWidget);
      expect(find.text(r'R$ 201,90'), findsOneWidget);
      // Dispensados de recolhimento: o que o prestador recebe é o líquido.
      expect(find.textContaining('art. 348'), findsOneWidget);
    });

    testWidgets('nota cancelada leva o carimbo e avisa que o pagamento continua no extrato',
        (tester) async {
      await pumpGolden(
          tester, child: _tela(NfseView(nota: fakeNotaFiscal(cancelada: true))));

      expect(find.text('NFS-e CANCELADA'), findsOneWidget);
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

    testWidgets('o recibo segue o art. 320 do Código Civil', (tester) async {
      await pumpGolden(
          tester, child: _tela(ComprovanteView(comprovante: fakeComprovante())));

      expect(find.byKey(const Key('comprovante-fundamento')), findsOneWidget);
      expect(find.textContaining('Código Civil, art. 320'), findsOneWidget);
      expect(find.byKey(const Key('comprovante-declaracao')), findsOneWidget);
      expect(find.textContaining('Recebemos de Ricardo Souza'), findsOneWidget);
      expect(find.text('quinhentos reais'), findsOneWidget);
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

    test('a NFS-e sai no leiaute do DANFSe, com a chave e os quadros oficiais', () async {
      final bytes = await DocumentoPdf.gerar(fakeDocumentoNota(retidos: true),
          comprimir: false);
      final texto = textoDoPdf(bytes);

      expect(texto, contains('DANFSe v2.0'));
      expect(texto, contains('Documento Auxiliar da NFS-e'));
      expect(texto, contains('Chave de Acesso da NFS-e'));
      expect(texto, contains('41069 02210 00000'));
      for (final quadro in [
        'TOMADOR DO SERVIÇO',
        'SERVIÇO PRESTADO',
        'TRIBUTAÇÃO MUNICIPAL (ISSQN)',
        'TRIBUTAÇÃO FEDERAL',
        'TRIBUTAÇÃO IBS / CBS',
        'VALOR TOTAL DA NFS-e',
        'INFORMAÇÕES COMPLEMENTARES',
      ]) {
        expect(texto, contains(quadro));
      }
      expect(texto, contains('Retido pelo Tomador'));
      expect(texto, contains('187,00'));
      expect(texto, contains('DOCUMENTO SIMULADO'));
    });

    test('o DANFSe cabe numa página A4, como o oficial — mesmo com IBS/CBS', () async {
      for (final doc in [
        fakeDocumentoNota(retidos: true),
        fakeDocumentoNota(anoDeTeste: true),
      ]) {
        final bytes = await DocumentoPdf.gerar(doc, comprimir: false);
        final paginas = RegExp(r'/Type\s*/Page(?!s)')
            .allMatches(String.fromCharCodes(bytes))
            .length;
        expect(paginas, 1);
      }
    });

    test('o recibo em PDF traz a quitação e o valor por extenso', () async {
      final bytes =
          await DocumentoPdf.gerar(fakeDocumentoComprovante(), comprimir: false);
      final texto = textoDoPdf(bytes);

      expect(texto, contains('Código Civil, art. 320'));
      expect(texto, contains('Recebemos de Ricardo Souza'));
      expect(texto, contains('quinhentos reais'));
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
