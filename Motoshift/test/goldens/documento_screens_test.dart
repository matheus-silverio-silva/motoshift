// Goldens dos documentos fiscais SIMULADOS: a NFS-e e o comprovante.
//
// O que a foto pega e a asserção não: a marca de simulação em cima do
// documento, a hierarquia entre valor do serviço e líquido, e o desenho das
// duas políticas de tributo lado a lado no histórico do repositório.

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
