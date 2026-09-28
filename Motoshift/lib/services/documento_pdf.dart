import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/documento_fiscal.dart';
import '../models/nota_fiscal.dart';
import '../utils/formato_fiscal.dart';
import 'identidade_pdf.dart';

/// O documento fiscal em PDF — NFS-e ou comprovante, SIMULADO.
///
/// Mesma ordem e mesmos textos da tela ([FormatoFiscal] formata os dois), e a
/// marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL" em dois lugares: numa faixa
/// no topo e em marca d'água diagonal por cima da página inteira. A faixa
/// informa; a marca d'água é a que sobrevive a recorte e print de tela.
///
/// Funciona no Flutter web: quem baixa e imprime é o pacote `printing`, com o
/// diálogo do navegador. O visual (cabeçalho, blocos, faixa, marca d'água)
/// mora em [IdentidadePdf], que as exportações de extrato, relatório e
/// informe também usam.
class DocumentoPdf {
  DocumentoPdf._();

  static const _cinza = IdentidadePdf.cinza;
  static const _vermelho = IdentidadePdf.vermelho;

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
    final (base, forte) =
        await IdentidadePdf.fontes(regular: regular, negrito: negrito);

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

  static pw.Widget _faixa(String marca) => IdentidadePdf.faixa(marca);

  static pw.Widget _marcaDagua(String marca) => IdentidadePdf.marcaDagua(marca);

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

  static pw.Widget _cabecalho(String sobretitulo, String titulo, List<String> linhas) =>
      IdentidadePdf.cabecalho(sobretitulo, titulo, linhas);

  static pw.Widget _bloco(String titulo, List<pw.Widget> filhos) =>
      IdentidadePdf.bloco(titulo, filhos);

  static pw.Widget _linha(String rotulo, String valor, {bool forte = false}) =>
      IdentidadePdf.linha(rotulo, valor, forte: forte);
}
