import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/utils/exportar_csv.dart';

import '../test_helpers.dart';

/// A planilha sai como arquivo, em UTF-8 com BOM.
///
/// Antes o CSV ia para a área de transferência com o aviso "cole numa
/// planilha" — nenhum arquivo era criado.
void main() {
  setUpAll(setupGoldenTests);

  test('o CSV começa com o BOM e guarda os acentos em UTF-8', () {
    const csv = 'data;descricao;valor\n2026-09-28;Farmácia Ana — Reposição;110.00\n';
    final bytes = csvComBom(csv);

    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes.sublist(3)), csv);
    // "á" em UTF-8 são dois bytes (C3 A1), não o E1 do Windows-1252.
    expect(bytes, containsAllInOrder([0xC3, 0xA1]));
  });

  testWidgets('exportar entrega um arquivo com o nome sugerido e diz quantas linhas',
      (tester) async {
    final baixados = fingirDownload();
    await pumpGolden(tester,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => entregarCsv(context, 'a;b\n1;2\n3;4\n',
                  nomeSugerido: 'relatorio.csv'),
              child: const Text('Exportar'),
            ),
          ),
        ));

    await tester.tap(find.text('Exportar'));
    await tester.pump();

    expect(baixados.single.nome, 'relatorio.csv');
    expect(baixados.single.mime, 'text/csv;charset=utf-8');
    expect(find.textContaining('relatorio.csv'), findsOneWidget);
    expect(find.textContaining('2 linhas'), findsOneWidget);
  });

  testWidgets('filtro sem nada não baixa arquivo vazio', (tester) async {
    final baixados = fingirDownload();
    await pumpGolden(tester,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  entregarCsv(context, 'a;b\n', nomeSugerido: 'extrato.csv'),
              child: const Text('Exportar'),
            ),
          ),
        ));

    await tester.tap(find.text('Exportar'));
    await tester.pump();

    expect(baixados, isEmpty);
    expect(find.text('Nada a exportar neste filtro.'), findsOneWidget);
  });
}
