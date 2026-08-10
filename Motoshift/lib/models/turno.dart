StatusTurno _parseStatus(String raw) {
  return switch (raw.toLowerCase()) {
    'em_andamento' || 'emandamento' => StatusTurno.emAndamento,
    'aceito' => StatusTurno.aceito,
    'finalizado' => StatusTurno.finalizado,
    'cancelado' => StatusTurno.cancelado,
    _ => StatusTurno.aberto,
  };
}

// Mapeado para a entidade `Turno` no Spring Boot / MySQL
// Tabela: turnos
class Turno {
  final int? id;
  final int lojistId;         // FK → usuarios.id (tipo = LOJISTA)
  final int? motoboyId;       // FK → usuarios.id (tipo = MOTOBOY), null = aberto
  final String titulo;
  final String? descricao;
  final String regiao;
  final DateTime dataInicio;
  final DateTime dataFim;
  final double valorEstimado;
  final double raioEntregaKm;
  final int vagas;             // total de vagas de entregador no turno
  final int vagasPreenchidas;  // quantas já foram aceitas
  final StatusTurno status;
  final PagamentoStatus pagamentoStatus;
  final DateTime? lojistaConfirmouEm;
  final DateTime? motoboyConfirmouEm;
  final double? distanciaPercorridaKm;
  final int? totalEntregas;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  const Turno({
    this.id,
    required this.lojistId,
    this.motoboyId,
    required this.titulo,
    this.descricao,
    required this.regiao,
    required this.dataInicio,
    required this.dataFim,
    required this.valorEstimado,
    required this.raioEntregaKm,
    this.vagas = 1,
    this.vagasPreenchidas = 0,
    this.status = StatusTurno.aberto,
    this.pagamentoStatus = PagamentoStatus.naoAplicavel,
    this.lojistaConfirmouEm,
    this.motoboyConfirmouEm,
    this.distanciaPercorridaKm,
    this.totalEntregas,
    this.criadoEm,
    this.atualizadoEm,
  });

  bool get lojistaJaConfirmou => lojistaConfirmouEm != null;
  bool get motoboyJaConfirmou => motoboyConfirmouEm != null;

  factory Turno.fromJson(Map<String, dynamic> json) {
    return Turno(
      id: json['id'] as int?,
      lojistId: json['lojistId'] as int,
      motoboyId: json['motoboyId'] as int?,
      titulo: json['titulo'] as String,
      descricao: json['descricao'] as String?,
      regiao: json['regiao'] as String,
      dataInicio: DateTime.parse(json['dataInicio'] as String),
      dataFim: DateTime.parse(json['dataFim'] as String),
      valorEstimado: (json['valorEstimado'] as num).toDouble(),
      raioEntregaKm: (json['raioEntregaKm'] as num).toDouble(),
      vagas: (json['vagas'] as num?)?.toInt() ?? 1,
      vagasPreenchidas: (json['vagasPreenchidas'] as num?)?.toInt() ?? 0,
      status: _parseStatus(json['status'] as String),
      pagamentoStatus: _parsePagamento(json['pagamentoStatus'] as String?),
      lojistaConfirmouEm: json['lojistaConfirmouEm'] != null
          ? DateTime.parse(json['lojistaConfirmouEm'] as String)
          : null,
      motoboyConfirmouEm: json['motoboyConfirmouEm'] != null
          ? DateTime.parse(json['motoboyConfirmouEm'] as String)
          : null,
      distanciaPercorridaKm: json['distanciaPercorridaKm'] != null
          ? (json['distanciaPercorridaKm'] as num).toDouble()
          : null,
      totalEntregas: json['totalEntregas'] as int?,
      criadoEm: json['criadoEm'] != null
          ? DateTime.parse(json['criadoEm'] as String)
          : null,
      atualizadoEm: json['atualizadoEm'] != null
          ? DateTime.parse(json['atualizadoEm'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'lojistId': lojistId,
      if (motoboyId != null) 'motoboyId': motoboyId,
      'titulo': titulo,
      if (descricao != null) 'descricao': descricao,
      'regiao': regiao,
      'dataInicio': dataInicio.toIso8601String(),
      'dataFim': dataFim.toIso8601String(),
      'valorEstimado': valorEstimado,
      'raioEntregaKm': raioEntregaKm,
      'vagas': vagas,
      'status': status.name.toUpperCase(),
    };
  }

  String get horarioFormatado {
    final hi = '${dataInicio.hour.toString().padLeft(2, '0')}:${dataInicio.minute.toString().padLeft(2, '0')}';
    final hf = '${dataFim.hour.toString().padLeft(2, '0')}:${dataFim.minute.toString().padLeft(2, '0')}';
    return '$hi - $hf';
  }

  Duration get duracao => dataFim.difference(dataInicio);

  /// Vagas ainda disponíveis (nunca negativo).
  int get vagasRestantes =>
      (vagas - vagasPreenchidas) < 0 ? 0 : (vagas - vagasPreenchidas);

  /// Turno que comporta mais de um entregador.
  bool get multiVaga => vagas > 1;
}

enum StatusTurno {
  aberto,
  aceito,
  emAndamento,
  finalizado,
  cancelado;

  String get label {
    return switch (this) {
      StatusTurno.aberto => 'Aberto',
      StatusTurno.aceito => 'Aceito',
      StatusTurno.emAndamento => 'Em Andamento',
      StatusTurno.finalizado => 'Finalizado',
      StatusTurno.cancelado => 'Cancelado',
    };
  }
}

PagamentoStatus _parsePagamento(String? raw) {
  return switch (raw?.toLowerCase()) {
    'pendente' => PagamentoStatus.pendente,
    'pago' => PagamentoStatus.pago,
    _ => PagamentoStatus.naoAplicavel,
  };
}

enum PagamentoStatus {
  naoAplicavel,
  pendente,
  pago;

  String get label {
    return switch (this) {
      PagamentoStatus.pendente => 'A receber',
      PagamentoStatus.pago => 'Pago',
      _ => '',
    };
  }
}
