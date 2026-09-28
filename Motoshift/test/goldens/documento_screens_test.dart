// Goldens dos documentos fiscais SIMULADOS: a NFS-e e o comprovante.
//
// O que a foto pega e a asserção não: a marca de simulação em cima do
// documento, o topo do DANFSe (chave de acesso, DPS e QR Code) e, na nota com
// retenção, os quadros de tributos e totais — o DANFSe é mais alto que a tela,
// e sem rolar as duas fotos seriam a mesma.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/documento_fiscal/documento_fiscal_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  testWidgets('DocumentoFiscalScreen — NFS-e sem retenção', (tester) async {
    await pumpGolden(
      tester,
      tipoUsuario: TipoUsuario.motoboy,
      child: const DocumentoFiscalScreen(),
      argumentos: DocumentoFiscalArgs(documento: fakeDocumentoNota()),
    );
    await expectLater(
      find.byType(DocumentoFiscalScreen),
      matchesGoldenFile('goldens/documento_nfse.png'),
    );
  });

  testWidgets('DocumentoFiscalScreen — NFS-e com retenção na fonte',
      (tester) async {
    await pumpGolden(
      tester,
      tipoUsuario: TipoUsuario.motoboy,
      child: const DocumentoFiscalScreen(),
      argumentos: DocumentoFiscalArgs(documento: fakeDocumentoNota(retidos: true)),
    );
    // Rola até os tributos: é onde as duas políticas se diferenciam.
    await tester.scrollUntilVisible(
      find.byKey(const Key('danfse-quadro-totais')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DocumentoFiscalScreen),
      matchesGoldenFile('goldens/documento_nfse_retida.png'),
    );
  });

  testWidgets('DocumentoFiscalScreen — recibo de recarga', (tester) async {
    await pumpGolden(
      tester,
      tipoUsuario: TipoUsuario.motoboy,
      child: const DocumentoFiscalScreen(),
      argumentos: DocumentoFiscalArgs(documento: fakeDocumentoComprovante()),
    );
    await expectLater(
      find.byType(DocumentoFiscalScreen),
      matchesGoldenFile('goldens/documento_comprovante.png'),
    );
  });
}
