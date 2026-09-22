import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/documento_fiscal.dart';
import '../models/nota_fiscal.dart';
import '../utils/formato_fiscal.dart';

/// O documento fiscal em PDF — NFS-e ou comprovante, SIMULADO.
///
/// Mesma ordem e mesmos textos da tela ([FormatoFiscal] formata os dois), e a
/// marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL" em dois lugares: numa faixa
/// no topo e em marca d'água diagonal por cima da página inteira. A faixa
/// informa; a marca d'água é a que sobrevive a recorte e print de tela.
///
/// Funciona no Flutter web: quem baixa e imprime é o pacote `printing`, com o
/// diálogo do navegador.
class DocumentoPdf {
  DocumentoPdf._();

  static const _teal = PdfColor.fromInt(0xFF0E7C7B);
  static const _cinza = PdfColor.fromInt(0xFF6B7280);
  static const _borda = PdfColor.fromInt(0xFFE5E7EB);
  static const _ambar = PdfColor.fromInt(0xFFFFF4DB);
  static const _vermelho = PdfColor.fromInt(0xFFC0392B);

  /// Nome sugerido para o arquivo baixado.
  static String nomeDoArquivo(DocumentoFiscal d) {
    final nota = d.nota;
    if (nota != null) return 'nfse-${nota.numero.toString().padLeft(6, '0')}-simulada.pdf';
    return '${d.comprovante!.numero.toLowerCase()}-simulado.pdf';
  }

  /// Gera o PDF. As fontes podem vir de fora (testes); sem elas, são lidas dos
  /// assets — a Roboto embutida, porque as fontes padrão do PDF só cobrem
  /// Latin-1 e quebram o "—" da própria marca.
  static Future<Uint8List> gerar(DocumentoFiscal d,
      {pw.Font? regular, pw.Font? negrito}) async {
    final base = regular ??
        pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Roboto-Regular.ttf'));
    final forte = negrito ??
        pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Roboto-Bold.ttf'));

    final doc = pw.Document(
      title: d.nota != null ? 'NFS-e simulada' : d.comprovante!.titulo,
      author: 'MotoShift (simulação)',
    );
    doc.addPage(pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: base, bold: forte),
        buildForeground: (_) => _marcaDagua(d.marca),
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _faixa(d.marca),
          pw.SizedBox(height: 14),
          if (d.nota != null) ..._nota(d.nota!) else ..._comprovante(d.comprovante!),
          pw.Spacer(),
          pw.Text(
            'Documento gerado pela plataforma MotoShift em ambiente de '
            'demonstração. Não foi transmitido a prefeitura nem à Receita e não '
            'tem validade fiscal.',
            style: const pw.TextStyle(fontSize: 8, color: _cinza),
          ),
        ],
      ),
    ));
    return doc.save();
  }

  // ── Partes do documento ────────────────────────────────────────────────

  static pw.Widget _faixa(String marca) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          color: _ambar,
          border: pw.Border.all(color: PdfColors.orange, width: 1),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(marca,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _marcaDagua(String marca) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Center(
          child: pw.Transform.rotate(
            angle: math.pi / 5,
            child: pw.Opacity(
              opacity: 0.12,
              child: pw.Text(marca,
                  style: pw.TextStyle(
                      fontSize: 34, fontWeight: pw.FontWeight.bold, color: _vermelho)),
            ),
          ),
        ),
      );

  static List<pw.Widget> _nota(NotaFiscal n) {
    final retidos = n.tributosRetidos;
    final sinal = retidos ? '− ' : '';
    return [
      _cabecalho('NOTA FISCAL DE SERVIÇO ELETRÔNICA', 'Nº ${n.numeroFormatado}', [
        'Emitida em ${FormatoFiscal.dataHora(n.emitidaEm)}',
        if (n.competencia != null) 'Competência: ${FormatoFiscal.data(n.competencia!)}',
      ]),
      pw.SizedBox(height: 12),
      _bloco('Prestador do serviço', [
        _linha('Nome', n.prestadorNome),
        _linha('Documento', FormatoFiscal.documento(n.prestadorDocumentoTipo, n.prestadorDocumento)),
        if (n.prestadorCidade != null) _linha('Cidade', n.prestadorCidade!),
      ]),
      _bloco('Tomador do serviço', [
        _linha('Nome', n.tomadorNome),
        _linha('Documento', FormatoFiscal.documento(n.tomadorDocumentoTipo, n.tomadorDocumento)),
        if (n.tomadorCidade != null) _linha('Cidade', n.tomadorCidade!),
      ]),
      _bloco('Discriminação do serviço', [pw.Text(n.descricaoServico)]),
      _bloco(retidos ? 'Valores e tributos retidos' : 'Valores e tributos', [
        _linha('Valor do serviço (base de cálculo)', FormatoFiscal.moeda(n.valorServico), forte: true),
        if (!retidos)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Text('Valor aproximado dos tributos (Lei 12.741/2012)',
                style: const pw.TextStyle(fontSize: 9, color: _cinza)),
          ),
        _linha('ISS (${FormatoFiscal.percentual(n.issAliquota)})', '$sinal${FormatoFiscal.moeda(n.issValor)}'),
        _linha('IRRF (${FormatoFiscal.percentual(n.irrfAliquota)})', '$sinal${FormatoFiscal.moeda(n.irrfValor)}'),
        _linha(retidos ? 'Total de tributos retidos' : 'Total aproximado de tributos',
            FormatoFiscal.moeda(n.totalTributos)),
        _linha('Valor líquido', FormatoFiscal.moeda(n.valorLiquido), forte: true),
      ]),
      _bloco('Autenticação', [
        _linha('Código de verificação', n.codigoVerificacao, forte: true),
        if (n.operacaoId != null) _linha('Operação no extrato', n.operacaoId!),
      ]),
      if (n.cancelada)
        pw.Text('NOTA CANCELADA${n.motivoCancelamento == null ? '' : ' — ${n.motivoCancelamento}'}',
            style: pw.TextStyle(color: _vermelho, fontWeight: pw.FontWeight.bold)),
    ];
  }

  static List<pw.Widget> _comprovante(Comprovante c) {
    final sinal = c.credito == null ? '' : (c.credito! ? '+ ' : '− ');
    return [
      _cabecalho(c.titulo.toUpperCase(), '$sinal${FormatoFiscal.moeda(c.valor)}', [
        'Nº ${c.numero}',
        FormatoFiscal.dataHora(c.dataHora),
      ]),
      pw.SizedBox(height: 12),
      _bloco('Titular', [
        _linha('Nome', c.titularNome),
        _linha('Documento', FormatoFiscal.documento(c.titularDocumentoTipo, c.titularDocumento)),
        if (c.titularCidade != null) _linha('Cidade', c.titularCidade!),
      ]),
      _bloco('Movimento', [
        if (c.descricao.isNotEmpty) _linha('Descrição', c.descricao),
        for (final l in c.detalhes) _linha(l.rotulo, l.valor),
        if (c.saldoDisponivelApos != null)
          _linha('Saldo disponível depois', FormatoFiscal.moeda(c.saldoDisponivelApos!)),
      ]),
      _bloco('Autenticação', [
        _linha('Código de autenticação', c.codigoAutenticacao, forte: true),
        if (c.operacaoId != null) _linha('Operação no extrato', c.operacaoId!),
      ]),
    ];
  }

  static pw.Widget _cabecalho(String sobretitulo, String titulo, List<String> linhas) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(color: _teal, borderRadius: pw.BorderRadius.circular(6)),
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

  static pw.Widget _bloco(String titulo, List<pw.Widget> filhos) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borda, width: 1),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(titulo.toUpperCase(),
              style: pw.TextStyle(fontSize: 8, color: _cinza, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          ...filhos,
        ],
      ),
    );
  }

  static pw.Widget _linha(String rotulo, String valor, {bool forte = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              flex: 4,
              child: pw.Text(rotulo, style: const pw.TextStyle(fontSize: 10, color: _cinza))),
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
}
