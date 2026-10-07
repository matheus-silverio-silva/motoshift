import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/dre.dart';
import '../models/extrato_filtro.dart';
import '../models/informe_anual.dart';
import '../models/resumo_financeiro.dart';
import '../models/transacao.dart';
import '../models/usuario.dart';
import '../utils/formato_fiscal.dart';
import 'identidade_pdf.dart';

/// Quem pediu o PDF: o nome no cabeçalho e o papel, que decide o que entra.
class TitularDoPdf {
  const TitularDoPdf({required this.nome, required this.papel});

  final String nome;
  final TipoUsuario papel;

  bool get souLojista => papel == TipoUsuario.lojista;

  /// Como o papel aparece no cabeçalho.
  String get rotuloDoPapel => souLojista
      ? 'Lojista — contratante do serviço'
      : 'Entregador — prestador de serviço';
}

/// As exportações em PDF — extrato, relatório financeiro e informe anual.
///
/// Geradas no app, com os pacotes `pdf` e `printing` e a identidade do
/// documento fiscal ([IdentidadePdf]). Cada uma traz um cabeçalho com nome,
/// papel, período e filtros aplicados, os mesmos números da tela e a tabela de
/// lançamentos.
///
/// <h3>O conteúdo segue o papel</h3>
/// Como na tela, o PDF do entregador não tem nada de lojista, e vice-versa: o
/// saldo bloqueado só é coluna para o lojista (o entregador nunca tem
/// bloqueado), os totais do relatório são os cartões do papel, e a ordem dos
/// tipos é a de [TipoTransacao.filtraveisPara].
///
/// <h3>O informe é o único documento simulado</h3>
/// Extrato e relatório são o que a plataforma registrou — não se passam por
/// documento de ninguém. O informe anual imita um documento fiscal, e por isso
/// leva a marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL" em faixa e em marca
/// d'água, como a NFS-e.
///
/// [comprimir] existe para os testes lerem o texto do PDF: comprimido, o
/// conteúdo das páginas não é legível sem descompactar.
class RelatorioPdf {
  RelatorioPdf._();

  // ── Extrato ────────────────────────────────────────────────────────────

  static String nomeDoExtrato(DateTime geradoEm) =>
      'extrato-${_iso(geradoEm)}.pdf';

  /// O extrato do filtro aplicado na tela, inteiro.
  static Future<Uint8List> extrato({
    required TitularDoPdf titular,
    required ExtratoFiltro filtro,
    required List<Transacao> lancamentos,
    required DateTime geradoEm,
    pw.Font? regular,
    pw.Font? negrito,
    bool comprimir = true,
  }) async {
    final totais = _totaisPorTipo(lancamentos, titular.papel);
    return _documento(
      titulo: 'Extrato da carteira',
      regular: regular,
      negrito: negrito,
      comprimir: comprimir,
      conteudo: [
        IdentidadePdf.cabecalho('EXTRATO DA CARTEIRA', titular.nome, [
          titular.rotuloDoPapel,
          'Período: ${_periodoDoFiltro(filtro)}',
          'Filtros: ${_filtrosAplicados(filtro)}',
          'Gerado em ${FormatoFiscal.dataHora(geradoEm)}',
        ]),
        pw.SizedBox(height: 12),
        IdentidadePdf.bloco('Resumo do que está listado', [
          IdentidadePdf.linha('Lançamentos', '${lancamentos.length}', forte: true),
          for (final t in totais)
            IdentidadePdf.linha('${t.tipo.label} (${t.quantidade}x)', _comSinal(t.total, t.credito)),
        ]),
        ..._tabelaDeLancamentos(lancamentos, titular),
      ],
      rodape: 'Extrato gerado pela plataforma MotoShift — os lançamentos que a '
          'carteira registrou, no filtro escolhido.',
    );
  }

  // ── Relatório ──────────────────────────────────────────────────────────

  static String nomeDoRelatorio(DateTime de, DateTime ate) =>
      'relatorio-${_iso(de)}-a-${_iso(ate)}.pdf';

  /// Os cartões do papel, a quebra por tipo, o fluxo e os lançamentos do
  /// período — o que a tela de relatórios mostra.
  static Future<Uint8List> relatorio({
    required TitularDoPdf titular,
    required DateTime de,
    required DateTime ate,
    required ResumoFinanceiro resumo,
    required List<PontoDeFluxo> fluxo,
    required List<Transacao> lancamentos,
    required DateTime geradoEm,
    Dre? dre,
    pw.Font? regular,
    pw.Font? negrito,
    bool comprimir = true,
  }) async {
    final ordem = TipoTransacao.filtraveisPara(titular.papel);
    int posicao(TotalPorTipo t) {
      final i = ordem.indexOf(t.tipo);
      return i < 0 ? ordem.length : i;
    }

    final porTipo = [...resumo.porTipo]..sort((a, b) => posicao(a).compareTo(posicao(b)));
    final fluxoComMovimento =
        fluxo.where((p) => p.entradas > 0 || p.saidas > 0).toList();

    return _documento(
      titulo: 'Relatório financeiro',
      regular: regular,
      negrito: negrito,
      comprimir: comprimir,
      conteudo: [
        IdentidadePdf.cabecalho('RELATÓRIO FINANCEIRO', titular.nome, [
          titular.rotuloDoPapel,
          'Período: ${FormatoFiscal.data(de)} a ${FormatoFiscal.data(ate)}',
          'Gerado em ${FormatoFiscal.dataHora(geradoEm)}',
        ]),
        pw.SizedBox(height: 12),
        IdentidadePdf.bloco('Resumo do período', [
          for (final n in ResumoFinanceiro.numerosPara(titular.papel, resumo))
            IdentidadePdf.linha(n.rotulo, n.valor == null ? '—' : FormatoFiscal.moeda(n.valor!),
                forte: true),
        ]),
        if (porTipo.isNotEmpty) ...[
          IdentidadePdf.secao('Por tipo de lançamento'),
          IdentidadePdf.tabela(
            colunas: const ['Tipo', 'Quantidade', 'Total'],
            alinharADireita: const {1, 2},
            linhas: [
              for (final t in porTipo)
                [
                  t.tipo.label,
                  '${t.quantidade}',
                  _comSinal(t.total, t.natureza?.isCredito),
                ],
            ],
          ),
        ],
        if (fluxoComMovimento.isNotEmpty) ...[
          IdentidadePdf.secao('Fluxo de caixa — o que entrou e saiu da carteira'),
          IdentidadePdf.tabela(
            colunas: const ['Período', 'Entrou', 'Saiu'],
            alinharADireita: const {1, 2},
            linhas: [
              for (final p in fluxoComMovimento)
                [p.rotulo, FormatoFiscal.moeda(p.entradas), FormatoFiscal.moeda(p.saidas)],
            ],
          ),
        ],
        if (dre != null) ..._demonstracaoDoResultado(dre),
        ..._tabelaDeLancamentos(lancamentos, titular),
      ],
      rodape: 'Relatório gerado pela plataforma MotoShift a partir do extrato '
          'da carteira.',
    );
  }

  /// A DRE do período (RF13): a situação por extenso e as linhas, cada uma
  /// com a origem. As mesmas linhas da tela de resultado, na mesma ordem — o
  /// PDF não refaz conta nenhuma.
  static List<pw.Widget> _demonstracaoDoResultado(Dre dre) {
    return [
      IdentidadePdf.secao('Demonstração do resultado'),
      IdentidadePdf.bloco('Situação', [
        IdentidadePdf.linha(dre.situacao.rotulo, dre.frase, forte: true),
        IdentidadePdf.linha(
            'Regime',
            'Caixa — o extrato da plataforma mais os custos e as receitas '
                'informados pelo usuário'),
        if (dre.lancamentosManuais == 0)
          IdentidadePdf.linha('Atenção',
              'Nenhum custo ou receita foi informado: o resultado ignora o que não passou pela plataforma'),
      ]),
      IdentidadePdf.tabela(
        colunas: const ['Linha', 'Origem', 'Valor'],
        alinharADireita: const {2},
        linhas: [
          for (final l in dre.linhas)
            [
              l.tipo == TipoDeLinhaDre.linha ? l.rotuloComSinal : '= ${l.rotulo}',
              l.origem.rotulo,
              FormatoFiscal.moeda(l.valor),
            ],
        ],
      ),
    ];
  }

  // ── Informe anual ──────────────────────────────────────────────────────

  static String nomeDoInforme(int ano) => 'informe-$ano-simulado.pdf';

  /// O informe anual SIMULADO — com a marca, em faixa e em marca d'água.
  static Future<Uint8List> informe({
    required TitularDoPdf titular,
    required InformeAnual informe,
    required DateTime geradoEm,
    pw.Font? regular,
    pw.Font? negrito,
    bool comprimir = true,
  }) async {
    final inf = informe;
    return _documento(
      titulo: '${inf.titulo} ${inf.ano} (simulado)',
      marca: inf.marca,
      regular: regular,
      negrito: negrito,
      comprimir: comprimir,
      conteudo: [
        IdentidadePdf.faixa(inf.marca),
        pw.SizedBox(height: 10),
        IdentidadePdf.cabecalho(inf.titulo.toUpperCase(), titular.nome, [
          titular.rotuloDoPapel,
          'Ano-calendário: ${inf.ano}',
          'Gerado em ${FormatoFiscal.dataHora(geradoEm)}',
        ]),
        pw.SizedBox(height: 12),
        IdentidadePdf.bloco('Totais do ano', [
          IdentidadePdf.linha(
              inf.souPrestador ? 'Total recebido' : 'Total de serviços tomados',
              FormatoFiscal.moeda(inf.total),
              forte: true),
          IdentidadePdf.linha('Pagamentos', '${inf.pagamentos}'),
          IdentidadePdf.linha('Com nota fiscal', '${inf.notasEmitidas}'),
          IdentidadePdf.linha('Sem nota fiscal', '${inf.semNota}'),
          if (inf.temRetencao) ...[
            IdentidadePdf.linha('ISS retido na fonte', FormatoFiscal.moeda(inf.issRetido)),
            IdentidadePdf.linha('IRRF retido na fonte', FormatoFiscal.moeda(inf.irrfRetido)),
          ],
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              'O total sai do extrato, pela data do pagamento: dinheiro recebido '
              'conta mesmo antes de a nota ser emitida.',
              style: const pw.TextStyle(fontSize: 8, color: IdentidadePdf.cinza),
            ),
          ),
        ]),
        IdentidadePdf.secao(inf.souPrestador ? 'Por fonte pagadora' : 'Por prestador'),
        if (inf.contrapartes.isEmpty)
          pw.Text('Nenhum pagamento em ${inf.ano}.',
              style: const pw.TextStyle(fontSize: 9, color: IdentidadePdf.cinza))
        else
          IdentidadePdf.tabela(
            colunas: [
              inf.souPrestador ? 'Fonte pagadora' : 'Prestador',
              'Documento',
              'Pagamentos',
              'Com nota',
              'Total',
            ],
            alinharADireita: const {2, 3, 4},
            linhas: [
              for (final c in inf.contrapartes)
                [
                  c.nome,
                  FormatoFiscal.documento(c.documentoTipo, c.documento),
                  '${c.pagamentos}',
                  '${c.notasEmitidas}',
                  FormatoFiscal.moeda(c.total),
                ],
            ],
          ),
        IdentidadePdf.secao('Por mês'),
        IdentidadePdf.tabela(
          colunas: const ['Mês', 'Pagamentos', 'Total'],
          alinharADireita: const {1, 2},
          linhas: [
            for (final m in inf.meses)
              [m.nome, '${m.pagamentos}', FormatoFiscal.moeda(m.total)],
          ],
        ),
      ],
      rodape: 'Informe gerado pela plataforma MotoShift em ambiente de '
          'demonstração. Não substitui o informe de rendimentos oficial e não '
          'tem validade fiscal.',
    );
  }

  // ── Apoio ──────────────────────────────────────────────────────────────

  static Future<Uint8List> _documento({
    required String titulo,
    required List<pw.Widget> conteudo,
    required String rodape,
    String? marca,
    pw.Font? regular,
    pw.Font? negrito,
    required bool comprimir,
  }) async {
    final (base, forte) =
        await IdentidadePdf.fontes(regular: regular, negrito: negrito);
    final doc = pw.Document(
      title: titulo,
      author: 'MotoShift',
      compress: comprimir,
    );
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: base, bold: forte),
        buildForeground: marca == null ? null : (_) => IdentidadePdf.marcaDagua(marca),
      ),
      footer: (contexto) => IdentidadePdf.rodape(contexto, rodape),
      build: (_) => conteudo,
    ));
    return doc.save();
  }

  /// Colunas do extrato por papel: o bloqueado só existe para o lojista.
  static List<pw.Widget> _tabelaDeLancamentos(
      List<Transacao> lancamentos, TitularDoPdf titular) {
    final colunas = [
      'Data',
      'Tipo',
      'Descrição',
      'Valor',
      titular.souLojista ? 'Disponível após' : 'Saldo após',
      if (titular.souLojista) 'Bloqueado após',
    ];
    return [
      IdentidadePdf.secao('Lançamentos'),
      if (lancamentos.isEmpty)
        pw.Text('Nenhum lançamento neste recorte.',
            style: const pw.TextStyle(fontSize: 9, color: IdentidadePdf.cinza))
      else
        IdentidadePdf.tabela(
          colunas: colunas,
          alinharADireita: {3, 4, if (titular.souLojista) 5},
          larguras: {
            0: const pw.FixedColumnWidth(62),
            1: const pw.FixedColumnWidth(78),
            2: const pw.FlexColumnWidth(),
            3: const pw.FixedColumnWidth(64),
            4: const pw.FixedColumnWidth(62),
            if (titular.souLojista) 5: const pw.FixedColumnWidth(62),
          },
          linhas: [
            for (final t in lancamentos)
              [
                FormatoFiscal.data(t.criadoEm),
                t.status.liquidado ? t.tipo.label : '${t.tipo.label} (${t.status.label.toLowerCase()})',
                t.descricao.isEmpty ? t.tipo.label : t.descricao,
                _comSinal(t.valor, t.credito),
                _talvez(t.saldoDisponivelApos),
                if (titular.souLojista) _talvez(t.saldoBloqueadoApos),
              ],
          ],
        ),
    ];
  }

  /// Soma por tipo do que está listado, na ordem de leitura do papel. Só
  /// lançamentos liquidados: pendente ainda não é dinheiro que se moveu.
  static List<_TotalListado> _totaisPorTipo(List<Transacao> lancamentos, TipoUsuario papel) {
    final porTipo = <TipoTransacao, _TotalListado>{};
    for (final t in lancamentos) {
      if (!t.status.liquidado) continue;
      final atual = porTipo[t.tipo];
      porTipo[t.tipo] = _TotalListado(
        t.tipo,
        (atual?.total ?? 0) + t.valor,
        (atual?.quantidade ?? 0) + 1,
        t.credito,
      );
    }
    final ordem = TipoTransacao.filtraveisPara(papel);
    int posicao(TipoTransacao t) {
      final i = ordem.indexOf(t);
      return i < 0 ? ordem.length : i;
    }

    return porTipo.values.toList()
      ..sort((a, b) => posicao(a.tipo).compareTo(posicao(b.tipo)));
  }

  static String _periodoDoFiltro(ExtratoFiltro f) {
    final de = f.dataInicio;
    final ate = f.dataFim;
    if (de == null && ate == null) return 'todo o histórico';
    if (de == null) return 'até ${FormatoFiscal.data(ate!)}';
    if (ate == null) return 'desde ${FormatoFiscal.data(de)}';
    return '${FormatoFiscal.data(de)} a ${FormatoFiscal.data(ate)}';
  }

  /// O que o filtro está deixando de fora, por extenso — sem o período, que
  /// tem linha própria.
  static String _filtrosAplicados(ExtratoFiltro f) {
    final partes = <String>[
      if (f.tipos.isNotEmpty)
        'tipos: ${f.tipos.map((t) => t.label.toLowerCase()).join(', ')}',
      if (f.natureza == NaturezaTransacao.credito) 'só entradas',
      if (f.natureza == NaturezaTransacao.debito) 'só saídas',
      if (f.turnoId != null) 'turno #${f.turnoId}',
      if (f.contraparteId != null) 'contraparte #${f.contraparteId}',
      if (f.valorMin != null) 'a partir de ${FormatoFiscal.moeda(f.valorMin!)}',
      if (f.valorMax != null) 'até ${FormatoFiscal.moeda(f.valorMax!)}',
      if (f.busca != null && f.busca!.isNotEmpty) 'busca "${f.busca}"',
    ];
    return partes.isEmpty ? 'nenhum' : partes.join('; ');
  }

  static String _comSinal(double valor, bool? credito) {
    final sinal = switch (credito) {
      true => '+ ',
      false => '− ',
      null => '',
    };
    return '$sinal${FormatoFiscal.moeda(valor)}';
  }

  static String _talvez(double? v) => v == null ? '—' : FormatoFiscal.moeda(v);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _TotalListado {
  const _TotalListado(this.tipo, this.total, this.quantidade, this.credito);

  final TipoTransacao tipo;
  final double total;
  final int quantidade;
  final bool? credito;
}
