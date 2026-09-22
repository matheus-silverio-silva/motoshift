/// Informe anual SIMULADO — de rendimentos, para o entregador; de serviços
/// tomados, para o lojista.
///
/// Espelha o `InformeAnualResponse` do backend. Os números vêm do extrato,
/// pela data do crédito (regime de caixa), e não das notas emitidas: recebimento
/// é dinheiro que entrou, tenha a nota sido gerada ou não. [notasEmitidas]
/// mostra, ao lado, quanto disso já está documentado.
class InformeAnual {
  const InformeAnual({
    required this.ano,
    required this.papel,
    required this.titulo,
    required this.total,
    required this.issRetido,
    required this.irrfRetido,
    required this.pagamentos,
    required this.notasEmitidas,
    required this.contrapartes,
    required this.meses,
    required this.marca,
  });

  final int ano;

  /// `prestador` (entregador) ou `tomador` (lojista).
  final String papel;
  final String titulo;
  final double total;
  final double issRetido;
  final double irrfRetido;
  final int pagamentos;
  final int notasEmitidas;
  final List<ContraparteDoInforme> contrapartes;
  final List<MesDoInforme> meses;
  final String marca;

  bool get souPrestador => papel == 'prestador';
  bool get temRetencao => issRetido > 0 || irrfRetido > 0;

  /// Quantos pagamentos ainda não viraram documento.
  int get semNota => pagamentos - notasEmitidas;

  factory InformeAnual.fromJson(Map<String, dynamic> json) {
    double num_(String chave) => (json[chave] as num?)?.toDouble() ?? 0;
    return InformeAnual(
      ano: (json['ano'] as num?)?.toInt() ?? DateTime.now().year,
      papel: json['papel'] as String? ?? 'prestador',
      titulo: json['titulo'] as String? ?? 'Informe anual',
      total: num_('total'),
      issRetido: num_('issRetido'),
      irrfRetido: num_('irrfRetido'),
      pagamentos: (json['pagamentos'] as num?)?.toInt() ?? 0,
      notasEmitidas: (json['notasEmitidas'] as num?)?.toInt() ?? 0,
      contrapartes: [
        for (final c in (json['contrapartes'] as List<dynamic>? ?? const []))
          ContraparteDoInforme.fromJson((c as Map).cast<String, dynamic>()),
      ],
      meses: [
        for (final m in (json['meses'] as List<dynamic>? ?? const []))
          MesDoInforme.fromJson((m as Map).cast<String, dynamic>()),
      ],
      marca: json['marca'] as String? ?? 'DOCUMENTO SIMULADO — SEM VALOR FISCAL',
    );
  }
}

/// O total com uma fonte pagadora (entregador) ou com um prestador (lojista).
class ContraparteDoInforme {
  const ContraparteDoInforme({
    required this.contraparteId,
    required this.nome,
    required this.documentoTipo,
    required this.total,
    required this.issRetido,
    required this.irrfRetido,
    required this.pagamentos,
    required this.notasEmitidas,
    this.documento,
  });

  final int? contraparteId;
  final String nome;
  final String documentoTipo;
  final String? documento;
  final double total;
  final double issRetido;
  final double irrfRetido;
  final int pagamentos;
  final int notasEmitidas;

  factory ContraparteDoInforme.fromJson(Map<String, dynamic> json) {
    double num_(String chave) => (json[chave] as num?)?.toDouble() ?? 0;
    return ContraparteDoInforme(
      contraparteId: (json['contraparteId'] as num?)?.toInt(),
      nome: json['nome'] as String? ?? '—',
      documentoTipo: json['documentoTipo'] as String? ?? 'CPF',
      documento: json['documento'] as String?,
      total: num_('total'),
      issRetido: num_('issRetido'),
      irrfRetido: num_('irrfRetido'),
      pagamentos: (json['pagamentos'] as num?)?.toInt() ?? 0,
      notasEmitidas: (json['notasEmitidas'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Mês de 1 a 12. Os doze sempre vêm, com zero onde não houve nada — é o que
/// deixa o gráfico honesto sobre o intervalo.
class MesDoInforme {
  const MesDoInforme({required this.mes, required this.total, required this.pagamentos});

  final int mes;
  final double total;
  final int pagamentos;

  factory MesDoInforme.fromJson(Map<String, dynamic> json) => MesDoInforme(
        mes: (json['mes'] as num?)?.toInt() ?? 1,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        pagamentos: (json['pagamentos'] as num?)?.toInt() ?? 0,
      );

  static const nomes = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  String get nome => nomes[(mes - 1).clamp(0, 11)];
}
