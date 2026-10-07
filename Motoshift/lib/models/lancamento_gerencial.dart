/// Uma categoria de lançamento gerencial — `GET /api/financeiro/categorias`.
///
/// O app não guarda a lista: pede a do papel de quem está logado. O
/// formulário é montado com o que vier.
class CategoriaDeLancamento {
  const CategoriaDeLancamento({
    required this.valor,
    required this.rotulo,
    this.grupo = '',
    this.rotuloDoGrupo = '',
    this.soma = false,
  });

  /// O que volta no `categoria` do lançamento ("combustivel").
  final String valor;
  final String rotulo;

  /// O grupo da DRE ("custo_variavel").
  final String grupo;
  final String rotuloDoGrupo;

  /// `true` se é receita.
  final bool soma;

  /// A única categoria com a calculadora de consumo.
  bool get ehCombustivel => valor == 'combustivel';

  factory CategoriaDeLancamento.fromJson(Map<String, dynamic> json) =>
      CategoriaDeLancamento(
        valor: json['valor'] as String? ?? '',
        rotulo: json['rotulo'] as String? ?? (json['valor'] as String? ?? ''),
        grupo: json['grupo'] as String? ?? '',
        rotuloDoGrupo: json['rotuloDoGrupo'] as String? ?? '',
        soma: json['soma'] as bool? ?? false,
      );
}

/// Um custo ou uma receita que o usuário informa para a DRE (RF13).
///
/// Não é lançamento do extrato: não move saldo e não tem documento fiscal. Por
/// isso é um modelo à parte de `Transacao`, e não um tipo a mais dela.
class LancamentoGerencial {
  const LancamentoGerencial({
    this.id,
    required this.categoria,
    this.rotuloDaCategoria = '',
    this.soma = false,
    required this.valor,
    required this.data,
    this.recorrente = false,
    this.recorrenteAte,
    this.turnoId,
    this.km,
    this.descricao,
    this.ocorrenciasNoPeriodo,
    this.valorNoPeriodo,
  });

  final int? id;

  /// O valor estável da categoria ("combustivel").
  final String categoria;
  final String rotuloDaCategoria;

  /// `true` se é receita; `false` se é custo, despesa ou dedução.
  final bool soma;

  /// O valor de UMA ocorrência.
  final double valor;

  /// O dia do pagamento (regime de caixa). No recorrente, dita o dia do mês.
  final DateTime data;
  final bool recorrente;
  final DateTime? recorrenteAte;
  final int? turnoId;
  final double? km;
  final String? descricao;

  /// Quantas vezes conta no período consultado; nulo fora de uma listagem.
  final int? ocorrenciasNoPeriodo;

  /// `valor × ocorrenciasNoPeriodo`: o peso deste lançamento na DRE do período.
  final double? valorNoPeriodo;

  /// Ainda não conta em período nenhum: a data dele é futura. A lista o
  /// mostra mesmo assim (zero ocorrências), para dar como corrigir — é a
  /// regra nova de um recorrente editado "a partir deste mês" cujo dia ainda
  /// não chegou.
  bool get aindaNaoConta => ocorrenciasNoPeriodo == 0;

  /// O que a lista mostra: o peso no período, ou o valor de uma ocorrência
  /// quando não há peso a mostrar.
  double get valorExibido =>
      aindaNaoConta ? valor : (valorNoPeriodo ?? valor);

  factory LancamentoGerencial.fromJson(Map<String, dynamic> json) {
    final categoria = json['categoria'] as String? ?? '';
    return LancamentoGerencial(
      id: (json['id'] as num?)?.toInt(),
      categoria: categoria,
      rotuloDaCategoria: json['rotuloDaCategoria'] as String? ?? categoria,
      soma: json['soma'] as bool? ?? false,
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      data: DateTime.tryParse(json['data'] as String? ?? '') ?? DateTime.now(),
      recorrente: json['recorrente'] as bool? ?? false,
      recorrenteAte: DateTime.tryParse(json['recorrenteAte'] as String? ?? ''),
      turnoId: (json['turnoId'] as num?)?.toInt(),
      km: (json['km'] as num?)?.toDouble(),
      descricao: json['descricao'] as String?,
      ocorrenciasNoPeriodo: (json['ocorrenciasNoPeriodo'] as num?)?.toInt(),
      valorNoPeriodo: (json['valorNoPeriodo'] as num?)?.toDouble(),
    );
  }

  /// O corpo de `POST` e `PUT /api/financeiro/lancamentos`. Só o que o
  /// usuário preenche: rótulo, grupo e ocorrências são do backend.
  Map<String, dynamic> toJson() => {
        'categoria': categoria,
        'valor': double.parse(valor.toStringAsFixed(2)),
        'data': _iso(data),
        'recorrente': recorrente,
        if (recorrente && recorrenteAte != null)
          'recorrenteAte': _iso(recorrenteAte!),
        if (turnoId != null) 'turnoId': turnoId,
        if (km != null) 'km': double.parse(km!.toStringAsFixed(1)),
        if (descricao != null && descricao!.trim().isNotEmpty)
          'descricao': descricao!.trim(),
      };

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A conta da calculadora de combustível do formulário:
/// km rodados ÷ consumo (km/l) × preço do litro.
///
/// Função pura, fora do formulário, para ter teste sem montar tela. Devolve
/// nulo quando falta algum dos três números ou algum não é positivo — a
/// calculadora não preenche nada com meia conta.
double? custoDoCombustivel({
  required double? km,
  required double? consumoKmPorLitro,
  required double? precoDoLitro,
}) {
  if (km == null || consumoKmPorLitro == null || precoDoLitro == null) {
    return null;
  }
  if (km <= 0 || consumoKmPorLitro <= 0 || precoDoLitro <= 0) return null;
  final valor = km / consumoKmPorLitro * precoDoLitro;
  // Centavos: é dinheiro.
  return (valor * 100).round() / 100;
}
