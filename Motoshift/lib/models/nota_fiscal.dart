/// Nota fiscal de serviço de um turno (NFS-e).
///
/// Espelha `NotaFiscalResponse` do backend. O prestador é sempre o entregador
/// e o tomador sempre o lojista; [papel] diz de que lado está quem abriu a
/// tela, para que a mesma tela sirva aos dois sem `if` de tipo de usuário.
class NotaFiscal {
  const NotaFiscal({
    required this.id,
    required this.turnoId,
    required this.numero,
    required this.serie,
    required this.codigoVerificacao,
    required this.prestadorId,
    required this.prestadorNome,
    required this.tomadorId,
    required this.tomadorNome,
    required this.descricaoServico,
    required this.valorServico,
    required this.issAliquota,
    required this.issValor,
    required this.irrfAliquota,
    required this.irrfValor,
    required this.totalTributos,
    required this.valorLiquido,
    required this.emitidaEm,
    required this.papel,
    this.prestadorDocumento,
    this.tomadorDocumento,
    this.competencia,
    this.canceladaEm,
    this.cancelada = false,
    this.motivoCancelamento,
  });

  final int id;
  final int turnoId;
  final int numero;
  final String serie;
  final String codigoVerificacao;

  final int prestadorId;
  final String prestadorNome;
  final String? prestadorDocumento;

  final int tomadorId;
  final String tomadorNome;
  final String? tomadorDocumento;

  final String descricaoServico;

  /// Data do serviço (início do turno) — diferente de [emitidaEm].
  final DateTime? competencia;

  final double valorServico;
  final double issAliquota;
  final double issValor;
  final double irrfAliquota;
  final double irrfValor;
  final double totalTributos;
  final double valorLiquido;

  final DateTime emitidaEm;
  final DateTime? canceladaEm;
  final bool cancelada;
  final String? motivoCancelamento;

  /// `prestador` (entregador) ou `tomador` (lojista), do ponto de vista de
  /// quem pediu a nota ao backend.
  final String papel;

  bool get souPrestador => papel == 'prestador';

  /// Número formatado como aparece no documento: "000123 / A1".
  String get numeroFormatado =>
      '${numero.toString().padLeft(6, '0')} / $serie';

  factory NotaFiscal.fromJson(Map<String, dynamic> json) {
    double num_(String chave) => (json[chave] as num?)?.toDouble() ?? 0.0;
    DateTime? data(String chave) {
      final v = json[chave];
      return v is String && v.isNotEmpty ? DateTime.parse(v) : null;
    }

    return NotaFiscal(
      id: json['id'] as int,
      turnoId: json['turnoId'] as int,
      numero: (json['numero'] as num?)?.toInt() ?? 0,
      serie: json['serie'] as String? ?? '',
      codigoVerificacao: json['codigoVerificacao'] as String? ?? '',
      prestadorId: json['prestadorId'] as int,
      prestadorNome: json['prestadorNome'] as String? ?? 'Entregador',
      prestadorDocumento: json['prestadorDocumento'] as String?,
      tomadorId: json['tomadorId'] as int,
      tomadorNome: json['tomadorNome'] as String? ?? 'Lojista',
      tomadorDocumento: json['tomadorDocumento'] as String?,
      descricaoServico: json['descricaoServico'] as String? ?? '',
      competencia: data('competencia'),
      valorServico: num_('valorServico'),
      issAliquota: num_('issAliquota'),
      issValor: num_('issValor'),
      irrfAliquota: num_('irrfAliquota'),
      irrfValor: num_('irrfValor'),
      totalTributos: num_('totalTributos'),
      valorLiquido: num_('valorLiquido'),
      emitidaEm: data('emitidaEm') ?? DateTime.now(),
      canceladaEm: data('canceladaEm'),
      cancelada: json['cancelada'] == true,
      motivoCancelamento: json['motivoCancelamento'] as String?,
      papel: json['papel'] as String? ?? 'tomador',
    );
  }
}

/// Turno concluído que ainda não gerou nota — o que a tela oferece para emitir.
class NotaFiscalPendente {
  const NotaFiscalPendente({
    required this.turnoId,
    required this.prestadorId,
    required this.tituloTurno,
    required this.dataInicio,
    required this.valorServico,
    required this.contraparteNome,
    required this.papel,
  });

  final int turnoId;
  final int prestadorId;
  final String tituloTurno;
  final DateTime dataInicio;
  final double valorServico;

  /// O outro lado da nota: o entregador, se quem olha é o lojista.
  final String contraparteNome;

  final String papel;

  factory NotaFiscalPendente.fromJson(Map<String, dynamic> json) {
    return NotaFiscalPendente(
      turnoId: json['turnoId'] as int,
      prestadorId: json['prestadorId'] as int,
      tituloTurno: json['tituloTurno'] as String? ?? 'Turno',
      dataInicio: DateTime.parse(json['dataInicio'] as String),
      valorServico: (json['valorServico'] as num?)?.toDouble() ?? 0.0,
      contraparteNome: json['contraparteNome'] as String? ?? '—',
      papel: json['papel'] as String? ?? 'prestador',
    );
  }
}
