import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A identidade visual dos PDFs do MotoShift, num lugar só.
///
/// Nasceu com o documento fiscal ([DocumentoPdf]) e passou a servir também às
/// exportações ([RelatorioPdf]): o mesmo cabeçalho verde, os mesmos blocos com
/// borda, a mesma fonte embutida e — nos documentos simulados — a mesma marca
/// em faixa e em marca d'água. Um extrato exportado e uma nota fiscal saem com
/// cara de que vieram do mesmo lugar, porque vieram.
class IdentidadePdf {
  IdentidadePdf._();

  static const teal = PdfColor.fromInt(0xFF0E7C7B);
  static const cinza = PdfColor.fromInt(0xFF6B7280);
  static const borda = PdfColor.fromInt(0xFFE5E7EB);
  static const ambar = PdfColor.fromInt(0xFFFFF4DB);
  static const vermelho = PdfColor.fromInt(0xFFC0392B);
  static const verde = PdfColor.fromInt(0xFF1E8E5A);
  static const fundoTabela = PdfColor.fromInt(0xFFF6F7F9);

  /// A Roboto embutida em `assets/fonts/pdf`. As fontes padrão do PDF só
  /// cobrem Latin-1 e quebram o "—" da própria marca de simulação.
  static Future<(pw.Font, pw.Font)> fontes({pw.Font? regular, pw.Font? negrito}) async {
    final base = regular ??
        pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Roboto-Regular.ttf'));
    final forte = negrito ??
        pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Roboto-Bold.ttf'));
    return (base, forte);
  }

  /// A faixa âmbar do topo — informa que o documento é simulado.
  static pw.Widget faixa(String marca) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          color: ambar,
          border: pw.Border.all(color: PdfColors.orange, width: 1),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(marca,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      );

  /// A marca d'água diagonal — a que sobrevive a recorte e print de tela.
  static pw.Widget marcaDagua(String marca) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Center(
          child: pw.Transform.rotate(
            angle: math.pi / 5,
            child: pw.Opacity(
              opacity: 0.12,
              child: pw.Text(marca,
                  style: pw.TextStyle(
                      fontSize: 34, fontWeight: pw.FontWeight.bold, color: vermelho)),
            ),
          ),
        ),
      );

  /// O bloco verde do topo: o que é, o título grande e as linhas de contexto.
  static pw.Widget cabecalho(String sobretitulo, String titulo, List<String> linhas) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(color: teal, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(sobretitulo, style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
          pw.SizedBox(height: 4),
          pw.Text(titulo,
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          for (final l in linhas)
            pw.Text(l, style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
        ],
      ),
    );
  }

  /// Um bloco com borda e título em caixa alta.
  static pw.Widget bloco(String titulo, List<pw.Widget> filhos) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borda, width: 1),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(titulo.toUpperCase(),
              style: pw.TextStyle(fontSize: 8, color: cinza, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          ...filhos,
        ],
      ),
    );
  }

  /// Rótulo à esquerda, valor à direita.
  static pw.Widget linha(String rotulo, String valor, {bool forte = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              flex: 4,
              child: pw.Text(rotulo, style: const pw.TextStyle(fontSize: 10, color: cinza))),
          pw.Expanded(
            flex: 6,
            child: pw.Text(valor,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: forte ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  /// Título de seção, fora de bloco — antes de uma tabela.
  static pw.Widget secao(String titulo) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
        child: pw.Text(titulo.toUpperCase(),
            style: pw.TextStyle(fontSize: 9, color: teal, fontWeight: pw.FontWeight.bold)),
      );

  /// Uma tabela no estilo da casa: cabeçalho verde, linhas zebradas e as
  /// colunas de [alinharADireita] (valores) encostadas à direita.
  static pw.Widget tabela({
    required List<String> colunas,
    required List<List<String>> linhas,
    Set<int> alinharADireita = const {},
    Map<int, pw.TableColumnWidth>? larguras,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: colunas,
      data: linhas,
      columnWidths: larguras,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: borda, width: 0.5),
        bottom: pw.BorderSide(color: borda, width: 0.5),
      ),
      headerDecoration: const pw.BoxDecoration(color: teal),
      headerStyle: pw.TextStyle(
          fontSize: 8.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      oddRowDecoration: const pw.BoxDecoration(color: fundoTabela),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      headerAlignments: {
        for (final i in alinharADireita) i: pw.Alignment.centerRight,
      },
      cellAlignments: {
        for (var i = 0; i < colunas.length; i++)
          i: alinharADireita.contains(i)
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
    );
  }

  /// Rodapé de página: de onde veio e em que página se está.
  static pw.Widget rodape(pw.Context contexto, String texto) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(texto, style: const pw.TextStyle(fontSize: 7.5, color: cinza)),
            ),
            pw.Text('Página ${contexto.pageNumber} de ${contexto.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.5, color: cinza)),
          ],
        ),
      );
}
