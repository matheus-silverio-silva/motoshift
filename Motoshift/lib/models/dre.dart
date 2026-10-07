import '../utils/formato_fiscal.dart';
import 'usuario.dart';

/// Como o período fechou.
enum SituacaoDre {
  lucro,
  prejuizo,
  equilibrio;

  /// Do texto do backend. Valor desconhecido vira equilíbrio — o estado que
  /// não comemora nem alarma.
  static SituacaoDre de(Object? valor) => switch (valor) {
        'lucro' => SituacaoDre.lucro,
        'prejuizo' => SituacaoDre.prejuizo,
        _ => SituacaoDre.equilibrio,
      };

  /// A palavra, para o rótulo do ícone e para o leitor de tela. A situação
  /// nunca é dita só pela cor.
  String get rotulo => switch (this) {
        SituacaoDre.lucro => 'Lucro',
        SituacaoDre.prejuizo => 'Prejuízo',
        SituacaoDre.equilibrio => 'Equilíbrio',
      };
}

/// "linha" comum, "subtotal" ou a última — o "resultado".
enum TipoDeLinhaDre {
  linha,
  subtotal,
  resultado;

  static TipoDeLinhaDre de(Object? valor) => switch (valor) {
        'subtotal' => TipoDeLinhaDre.subtotal,
        'resultado' => TipoDeLinhaDre.resultado,
        _ => TipoDeLinhaDre.linha,
      };
}

/// De onde veio o número de uma linha.
enum OrigemDaLinha {
  /// A plataforma registrou: está no extrato.
  extrato,

  /// O usuário informou: é um lançamento gerencial.
  manual,

  /// Soma das linhas de cima.
  calculado;

  static OrigemDaLinha de(Object? valor) => switch (valor) {
        'extrato' => OrigemDaLinha.extrato,
        'manual' => OrigemDaLinha.manual,
        _ => OrigemDaLinha.calculado,
      };

  /// Como a tabela diz a origem; vazio no subtotal, que não tem uma.
  String get rotulo => switch (this) {
        OrigemDaLinha.extrato => 'Extrato',
        OrigemDaLinha.manual => 'Informado por você',
        OrigemDaLinha.calculado => '',
      };
}

/// Uma linha da demonstração.
class LinhaDre {
  const LinhaDre({
    required this.chave,
    required this.rotulo,
    required this.valor,
    this.tipo = TipoDeLinhaDre.linha,
    this.origem = OrigemDaLinha.calculado,
    this.subtrai = false,
  });

  /// Identificador estável ("receita_bruta", "combustivel").
  final String chave;
  final String rotulo;

  /// Magnitude nas linhas comuns; com sinal nos subtotais e no resultado.
  final double valor;
  final TipoDeLinhaDre tipo;
  final OrigemDaLinha origem;

  /// As linhas que se tiram da de cima — as do "(−)".
  final bool subtrai;

  /// "(−) Combustível", como numa DRE impressa.
  String get rotuloComSinal => subtrai ? '(−) $rotulo' : rotulo;

  /// Linha comum sem valor no período. A tela e o PDF não a mostram — a
  /// retenção na fonte de quem não tem retenção, o seguro de quem não tem
  /// seguro. Subtotal e resultado nunca são "zerados": são a conta, e
  /// aparecem mesmo valendo zero.
  bool get zerada => tipo == TipoDeLinhaDre.linha && valor == 0;

  factory LinhaDre.fromJson(Map<String, dynamic> json) => LinhaDre(
        chave: json['chave'] as String? ?? '',
        rotulo: json['rotulo'] as String? ?? '',
        valor: _numero(json['valor']) ?? 0,
        tipo: TipoDeLinhaDre.de(json['tipo']),
        origem: OrigemDaLinha.de(json['origem']),
        subtrai: json['subtrai'] as bool? ?? false,
      );
}

/// O período de comparação: o imediatamente anterior, do mesmo tamanho.
class DreAnterior {
  const DreAnterior({
    required this.dataInicio,
    required this.dataFim,
    required this.resultado,
    required this.situacao,
  });

  final DateTime dataInicio;
  final DateTime dataFim;
  final double resultado;
  final SituacaoDre situacao;

  static DreAnterior? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final de = _data(json['dataInicio']);
    final ate = _data(json['dataFim']);
    if (de == null || ate == null) return null;
    return DreAnterior(
      dataInicio: de,
      dataFim: ate,
      resultado: _numero(json['resultado']) ?? 0,
      situacao: SituacaoDre.de(json['situacao']),
    );
  }
}

/// A DRE simplificada de um período — `GET /api/financeiro/dre` (RF13).
///
/// O backend monta uma para cada papel; a forma é a mesma, e a tela não
/// decide nada: mostra as [linhas] na ordem em que vieram.
///
/// O `fromJson` tolera campo ausente, como os outros modelos: uma versão do
/// backend sem um indicador não derruba a tela — o cartão dele some.
class Dre {
  const Dre({
    required this.papel,
    required this.dataInicio,
    required this.dataFim,
    required this.linhas,
    required this.resultado,
    required this.situacao,
    this.indicadores = const {},
    this.anterior,
    this.variacaoResultado,
    this.lancamentosManuais = 0,
  });

  final TipoUsuario papel;
  final DateTime dataInicio;
  final DateTime dataFim;
  final List<LinhaDre> linhas;
  final double resultado;
  final SituacaoDre situacao;

  /// Chaves estáveis; o valor pode ser nulo quando a conta não existe
  /// (margem sem receita, ponto de equilíbrio com margem negativa).
  final Map<String, dynamic> indicadores;
  final DreAnterior? anterior;

  /// Resultado deste período menos o do anterior, em REAIS.
  final double? variacaoResultado;

  /// Quantos lançamentos informados à mão entraram na conta.
  final int lancamentosManuais;

  bool get souLojista => papel == TipoUsuario.lojista;

  /// "Lucro de R$ 1.240,00 no período" — a situação por extenso. A faixa da
  /// tela, o leitor de tela e o PDF dizem a mesma frase.
  String get frase => switch (situacao) {
        SituacaoDre.lucro =>
          'Lucro de ${FormatoFiscal.moeda(resultado.abs())} no período',
        SituacaoDre.prejuizo =>
          'Prejuízo de ${FormatoFiscal.moeda(resultado.abs())} no período',
        SituacaoDre.equilibrio => 'Sem lucro nem prejuízo no período',
      };

  /// Um indicador numérico, ou nulo se não veio ou não se aplica.
  double? numero(String chave) => _numero(indicadores[chave]);

  int? inteiro(String chave) => _numero(indicadores[chave])?.round();

  String? texto(String chave) => indicadores[chave] as String?;

  LinhaDre? linha(String chave) {
    for (final l in linhas) {
      if (l.chave == chave) return l;
    }
    return null;
  }

  factory Dre.fromJson(Map<String, dynamic> json) {
    final hoje = DateTime.now();
    return Dre(
      papel: json['papel'] == 'lojista' ? TipoUsuario.lojista : TipoUsuario.motoboy,
      dataInicio: _data(json['dataInicio']) ?? DateTime(hoje.year, hoje.month, 1),
      dataFim: _data(json['dataFim']) ?? hoje,
      linhas: [
        for (final l in (json['linhas'] as List<dynamic>? ?? const []))
          if (l is Map<String, dynamic>) LinhaDre.fromJson(l),
      ],
      resultado: _numero(json['resultado']) ?? 0,
      situacao: SituacaoDre.de(json['situacao']),
      indicadores: (json['indicadores'] as Map<String, dynamic>?) ?? const {},
      anterior: DreAnterior.fromJson(json['anterior']),
      variacaoResultado: _numero(json['variacaoResultado']),
      lancamentosManuais: (json['lancamentosManuais'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Um mês do gráfico anual — `GET /api/financeiro/dre/mensal`.
class MesDre {
  const MesDre({
    required this.mes,
    required this.rotulo,
    required this.receita,
    required this.custos,
    required this.resultado,
  });

  /// 1 a 12.
  final int mes;

  /// "Jan", "Fev", ...
  final String rotulo;
  final double receita;
  final double custos;
  final double resultado;

  bool get semMovimento => receita == 0 && custos == 0;

  factory MesDre.fromJson(Map<String, dynamic> json) => MesDre(
        mes: (json['mes'] as num?)?.toInt() ?? 0,
        rotulo: json['rotulo'] as String? ?? '',
        receita: _numero(json['receita']) ?? 0,
        custos: _numero(json['custos']) ?? 0,
        resultado: _numero(json['resultado']) ?? 0,
      );
}

double? _numero(Object? v) => v is num ? v.toDouble() : null;

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v) : null;
