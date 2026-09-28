import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/danfse.dart';
import '../models/documento_fiscal.dart';
import '../models/nota_fiscal.dart';
import '../utils/formato_fiscal.dart';
import 'identidade_pdf.dart';

/// O documento fiscal em PDF — NFS-e ou comprovante, SIMULADO.
///
/// A NFS-e sai no leiaute do DANFSe v2.0 (Nota Técnica SE/CGNFS-e nº
/// 008/2026): cabeçalho sombreado, chave de acesso, a grade de identificação
/// com o QR Code ao lado e os quadros oficiais — os mesmos que a tela desenha,
/// vindos prontos do backend. O comprovante segue o visual da casa.
///
/// A marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL" vai em dois lugares: numa
/// faixa no topo e em marca d'água diagonal por cima da página inteira. A
/// faixa informa; a marca d'água é a que sobrevive a recorte e print de tela.
///
/// Funciona no Flutter web: quem baixa e imprime é o pacote `printing`, com o
/// diálogo do navegador.
class DocumentoPdf {
  DocumentoPdf._();

  static const _cinza = IdentidadePdf.cinza;
  static const _vermelho = IdentidadePdf.vermelho;

  /// O cinza claro que a NT 008 manda usar no cabeçalho e no valor final.
  static const _sombra = PdfColor.fromInt(0xFFE6E6E6);
  static const _bordaDanfse = PdfColor.fromInt(0xFF9CA3AF);

  static const _margem = 22.0;
  static const _respiro = 4.0;

  /// A largura útil dentro de um quadro: página menos margens, borda e padding.
  static final _larguraQuadro = PdfPageFormat.a4.width - 2 * _margem - 2 * _respiro - 2;

  /// Nome sugerido para o arquivo baixado.
  static String nomeDoArquivo(DocumentoFiscal d) {
    final nota = d.nota;
    if (nota != null) return 'nfse-${nota.numero.toString().padLeft(6, '0')}-simulada.pdf';
    return '${d.comprovante!.numero.toLowerCase()}-simulado.pdf';
  }

  /// Gera o PDF. As fontes podem vir de fora (testes); sem elas, são lidas dos
  /// assets — a Roboto embutida, porque as fontes padrão do PDF só cobrem
  /// Latin-1 e quebram o "—" da própria marca. (A NT 008 pede Arial nos
  /// títulos e MS Sans Serif no conteúdo; a Roboto é a sans-serif que pode ir
  /// embutida.)
  ///
  /// [comprimir] existe para os testes lerem o texto do PDF, como nas
  /// exportações do `RelatorioPdf`.
  static Future<Uint8List> gerar(DocumentoFiscal d,
      {pw.Font? regular, pw.Font? negrito, bool comprimir = true}) async {
    final (base, forte) =
        await IdentidadePdf.fontes(regular: regular, negrito: negrito);

    final doc = pw.Document(
      title: d.nota != null ? 'DANFSe — NFS-e simulada' : d.comprovante!.titulo,
      author: 'MotoShift (simulação)',
      compress: comprimir,
    );
    final tema = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margem),
      theme: pw.ThemeData.withFont(base: base, bold: forte),
      buildForeground: (_) => _marcaDagua(d.marca),
    );
    const rodape = 'Documento gerado pela plataforma MotoShift em ambiente de '
        'demonstração. Não foi transmitido ao Sistema Nacional NFS-e, à '
        'prefeitura nem à Receita e não tem validade fiscal.';

    final nota = d.nota;
    if (nota != null) {
      // O DANFSe cabe numa página A4, como o oficial. MultiPage mesmo assim:
      // uma descrição de serviço longa não pode derrubar a geração do
      // arquivo — e aí cada quadro vai inteiro para a página seguinte.
      doc.addPage(pw.MultiPage(
        pageTheme: tema,
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: _faixa(d.marca),
        ),
        footer: (ctx) => IdentidadePdf.rodape(ctx, rodape),
        build: (_) => _nota(nota),
      ));
    } else {
      doc.addPage(pw.Page(
        pageTheme: tema,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _faixa(d.marca),
            pw.SizedBox(height: 14),
            ..._comprovante(d.comprovante!),
            pw.Spacer(),
            pw.Text(rodape, style: const pw.TextStyle(fontSize: 8, color: _cinza)),
          ],
        ),
      ));
    }
    return doc.save();
  }

  // ── Partes do documento ────────────────────────────────────────────────

  static pw.Widget _faixa(String marca) => IdentidadePdf.faixa(marca);

  static pw.Widget _marcaDagua(String marca) => IdentidadePdf.marcaDagua(marca);

  // ── NFS-e: DANFSe v2.0 ─────────────────────────────────────────────────

  static List<pw.Widget> _nota(NotaFiscal n) {
    final d = n.danfse;
    if (d == null) {
      // Nota de um backend anterior ao leiaute: o essencial, e o porquê.
      return [
        _cabecalho('NOTA FISCAL DE SERVIÇO ELETRÔNICA', 'Nº ${n.numeroFormatado}', [
          'Emitida em ${FormatoFiscal.dataHora(n.emitidaEm)}',
        ]),
        pw.SizedBox(height: 10),
        _linha('Valor líquido', FormatoFiscal.moeda(n.valorLiquido), forte: true),
        pw.Text('O servidor não enviou o leiaute do DANFSe desta nota.',
            style: const pw.TextStyle(fontSize: 9, color: _cinza)),
      ];
    }
    return [
      _cabecalhoDanfse(d),
      pw.Inseparable(child: _identificacao(n, d)),
      for (final q in d.quadros) pw.Inseparable(child: _quadro(q)),
      if (n.cancelada)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 4),
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _vermelho, width: 1.5)),
          child: pw.Text(
            'NFS-e CANCELADA'
            '${n.canceladaEm == null ? '' : ' em ${FormatoFiscal.dataHoraDocumento(n.canceladaEm!)}'}'
            '${n.motivoCancelamento == null ? '' : ' — ${n.motivoCancelamento}'}',
            style: pw.TextStyle(color: _vermelho, fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ),
    ];
  }

  /// O topo do DANFSe, sombreado: o que é o documento e onde foi emitido.
  /// Sem brasão nem nome de prefeitura — o documento é simulado.
  static pw.Widget _cabecalhoDanfse(Danfse d) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: _sombra,
        border: pw.Border.all(color: _bordaDanfse, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            color: PdfColors.black,
            child: pw.Text('NFS-e',
                style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(d.versao,
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('Documento Auxiliar da NFS-e', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Município emissor', style: const pw.TextStyle(fontSize: 6.5, color: _cinza)),
              pw.Text(d.municipioEmissor,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(d.norma, style: const pw.TextStyle(fontSize: 6.5, color: _cinza)),
            ],
          ),
        ],
      ),
    );
  }

  /// Chave de acesso, a grade de identificação e o QR Code ao lado.
  static pw.Widget _identificacao(NotaFiscal n, Danfse d) {
    final campos = [
      CampoDanfse('Número da NFS-e', n.numero.toString()),
      CampoDanfse('Competência da NFS-e',
          n.competencia == null ? '-' : FormatoFiscal.data(n.competencia!)),
      CampoDanfse('Data e Hora da emissão da NFS-e', FormatoFiscal.dataHoraDocumento(n.emitidaEm)),
      CampoDanfse('Número da DPS', d.numeroDps?.toString() ?? '-'),
      CampoDanfse('Série da DPS', d.serieDps ?? '-'),
      CampoDanfse('Data e Hora da emissão da DPS', FormatoFiscal.dataHoraDocumento(n.emitidaEm)),
    ];
    // O QR Code tem 2,3 cm — a NT pede no mínimo 1,52 cm.
    const qr = 66.0;
    final larguraGrade = _larguraQuadro - qr - 10;
    return _moldura(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _rotulo('Chave de Acesso da NFS-e'),
                pw.Text(d.chaveFormatada,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                _grade(campos, larguraGrade, colunas: 3),
                pw.SizedBox(height: 3),
                pw.Text(d.avisoQrCode,
                    style: const pw.TextStyle(fontSize: 6, color: _cinza)),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: d.conteudoQrCode,
            width: qr,
            height: qr,
          ),
        ],
      ),
    );
  }

  /// Um quadro: a barra de título sombreada, a grade e a observação. O
  /// quadro sem campos (destinatário, intermediário) é uma linha só, como no
  /// DANFSe oficial.
  static pw.Widget _quadro(QuadroDanfse q) {
    if (q.campos.isEmpty) {
      final negrito = pw.TextStyle(fontWeight: pw.FontWeight.bold);
      return _moldura(pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 7.5),
          children: q.observacaoRepeteTitulo
              ? [pw.TextSpan(text: q.observacao, style: negrito)]
              : [
                  pw.TextSpan(text: '${q.titulo}: ', style: negrito),
                  pw.TextSpan(text: q.observacao ?? '-'),
                ],
        ),
      ));
    }
    return _moldura(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
            color: _sombra,
            child: pw.Text(q.titulo,
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 3),
          _grade(q.campos, _larguraQuadro),
          if (q.observacao != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(q.observacao!, style: const pw.TextStyle(fontSize: 6, color: _cinza)),
          ],
        ],
      ),
    );
  }

  /// A grade de campos do DANFSe: cinco colunas, densa como a do documento
  /// oficial — é o que faz a nota caber numa página A4 mesmo com o quadro de
  /// IBS/CBS preenchido. Campo largo ocupa duas colunas — nome, endereço — ou
  /// a linha inteira quando o texto é comprido (a descrição do serviço, o
  /// código de tributação por extenso).
  static pw.Widget _grade(List<CampoDanfse> campos, double largura, {int colunas = 5}) {
    const espaco = 4.0;
    final celula = (largura - espaco * (colunas - 1)) / colunas;
    double larguraDe(CampoDanfse c) {
      if (!c.largo) return celula;
      return c.valor.length <= 60 ? celula * 2 + espaco : largura;
    }

    return pw.Wrap(
      spacing: espaco,
      runSpacing: 2,
      children: [
        for (final c in campos)
          pw.Container(
            width: larguraDe(c),
            padding: c.destaque
                ? const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2)
                : pw.EdgeInsets.zero,
            color: c.destaque ? _sombra : null,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _rotulo(c.rotulo),
                pw.Text(c.valor,
                    style: pw.TextStyle(
                        fontSize: c.destaque ? 9 : 7.5,
                        fontWeight: c.destaque ? pw.FontWeight.bold : pw.FontWeight.normal)),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _rotulo(String texto) =>
      pw.Text(texto, style: const pw.TextStyle(fontSize: 6, color: _cinza));

  static pw.Widget _moldura(pw.Widget filho) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(top: 3),
        padding: const pw.EdgeInsets.all(_respiro),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _bordaDanfse, width: 0.8)),
        child: filho,
      );

  // ── Comprovantes ───────────────────────────────────────────────────────

  static List<pw.Widget> _comprovante(Comprovante c) {
    final sinal = c.credito == null ? '' : (c.credito! ? '+ ' : '− ');
    return [
      _cabecalho(c.titulo.toUpperCase(), '$sinal${FormatoFiscal.moeda(c.valor)}', [
        'Nº ${c.numero}',
        FormatoFiscal.dataHora(c.dataHora),
        if (c.fundamento != null) c.fundamento!,
      ]),
      pw.SizedBox(height: 12),
      if (c.declaracao != null)
        _bloco('Recibo', [
          pw.Text(c.declaracao!, style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
        ]),
      _bloco('Titular', [
        _linha('Nome', c.titularNome),
        _linha('Documento', FormatoFiscal.documento(c.titularDocumentoTipo, c.titularDocumento)),
        if (c.titularCidade != null) _linha('Cidade', c.titularCidade!),
      ]),
      _bloco('Movimento', [
        if (c.descricao.isNotEmpty) _linha('Descrição', c.descricao),
        if (c.valorPorExtenso != null && c.declaracao != null)
          _linha('Valor por extenso', c.valorPorExtenso!),
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
