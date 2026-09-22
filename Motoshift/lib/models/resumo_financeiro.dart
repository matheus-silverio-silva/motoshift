import 'transacao.dart';

/// O retrato financeiro do período, como o backend o devolve em `/resumo`.
///
/// Serve aos dois perfis: o que é específico de cada papel tem nome próprio —
/// [aReceber] é do entregador, [comprometido] e [reservasAbertas] são do
/// lojista — e vem zerado para quem não tem aquele tipo de pendência.
class ResumoFinanceiro {
  final DateTime dataInicio;
  final DateTime dataFim;
  final double entradas;
  final double saidas;
  final double liquido;
  final double disponivel;
  final double bloqueado;

  /// Entregador: turnos aceitos que ainda não foram finalizados.
  ///
  /// Não é saldo. O dinheiro está bloqueado na carteira do lojista, não na
  /// dele, e o turno ainda pode ser cancelado — por isso aparece separado.
  final double aReceber;

  /// Lojista: total das reservas abertas. É o mesmo número de [bloqueado],
  /// mostrado ao lado da lista que o explica.
  final double comprometido;

  final List<ReservaAberta> reservasAbertas;
  final List<TotalPorTipo> porTipo;

  const ResumoFinanceiro({
    required this.dataInicio,
    required this.dataFim,
    required this.entradas,
    required this.saidas,
    required this.liquido,
    required this.disponivel,
    required this.bloqueado,
    required this.aReceber,
    required this.comprometido,
    this.reservasAbertas = const [],
    this.porTipo = const [],
  });

  factory ResumoFinanceiro.fromJson(Map<String, dynamic> json) {
    return ResumoFinanceiro(
      dataInicio: DateTime.parse(json['dataInicio'] as String),
      dataFim: DateTime.parse(json['dataFim'] as String),
      entradas: _num(json['entradas']),
      saidas: _num(json['saidas']),
      liquido: _num(json['liquido']),
      disponivel: _num(json['disponivel']),
      bloqueado: _num(json['bloqueado']),
      aReceber: _num(json['aReceber']),
      comprometido: _num(json['comprometido']),
      reservasAbertas: (json['reservasAbertas'] as List<dynamic>? ?? [])
          .map((e) => ReservaAberta.fromJson(e as Map<String, dynamic>))
          .toList(),
      porTipo: (json['porTipo'] as List<dynamic>? ?? [])
          .map((e) => TotalPorTipo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  double get saldoTotal => disponivel + bloqueado;
}

/// Quanto um turno específico ainda segura na carteira do lojista.
class ReservaAberta {
  final int turnoId;
  final String titulo;
  final double valor;

  const ReservaAberta({
    required this.turnoId,
    required this.titulo,
    required this.valor,
  });

  factory ReservaAberta.fromJson(Map<String, dynamic> json) => ReservaAberta(
        turnoId: json['turnoId'] as int,
        titulo: json['titulo'] as String? ?? 'Turno',
        valor: _num(json['valor']),
      );
}

/// Uma linha da quebra por tipo, com a natureza já resolvida pelo backend.
class TotalPorTipo {
  final TipoTransacao tipo;
  final NaturezaTransacao? natureza;
  final double total;
  final int quantidade;

  const TotalPorTipo({
    required this.tipo,
    this.natureza,
    required this.total,
    required this.quantidade,
  });

  factory TotalPorTipo.fromJson(Map<String, dynamic> json) {
    final bruto = Transacao.fromJson({
      'tipo': json['tipo'],
      'natureza': json['natureza'],
      'valor': json['total'],
      'descricao': '',
      'status': 'concluido',
      'criadoEm': DateTime.now().toIso8601String(),
      'usuarioId': 0,
    });
    return TotalPorTipo(
      tipo: bruto.tipo,
      natureza: bruto.natureza,
      total: _num(json['total']),
      quantidade: (json['quantidade'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Um ponto da série de fluxo de caixa.
class PontoDeFluxo {
  final DateTime inicio;
  final String rotulo;
  final double entradas;
  final double saidas;
  final double liquido;

  const PontoDeFluxo({
    required this.inicio,
    required this.rotulo,
    required this.entradas,
    required this.saidas,
    required this.liquido,
  });

  factory PontoDeFluxo.fromJson(Map<String, dynamic> json) => PontoDeFluxo(
        inicio: DateTime.parse(json['inicio'] as String),
        rotulo: json['rotulo'] as String? ?? '',
        entradas: _num(json['entradas']),
        saidas: _num(json['saidas']),
        liquido: _num(json['liquido']),
      );
}

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
