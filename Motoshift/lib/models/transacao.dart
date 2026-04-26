TipoTransacao _parseTipo(String raw) {
  return switch (raw.toLowerCase()) {
    'turno' => TipoTransacao.turno,
    'bonus' => TipoTransacao.bonus,
    'saque' => TipoTransacao.saque,
    _ => TipoTransacao.turno,
  };
}

// Mapeado para a entidade `Transacao` no Spring Boot / MySQL
// Tabela: transacoes
class Transacao {
  final int? id;
  final int motoboyId;          // FK → usuarios.id
  final int? turnoId;           // FK → turnos.id (pode ser null p/ bônus)
  final TipoTransacao tipo;
  final double valor;
  final String descricao;
  final StatusTransacao status;
  final DateTime criadoEm;

  const Transacao({
    this.id,
    required this.motoboyId,
    this.turnoId,
    required this.tipo,
    required this.valor,
    required this.descricao,
    this.status = StatusTransacao.processado,
    required this.criadoEm,
  });

  factory Transacao.fromJson(Map<String, dynamic> json) {
    return Transacao(
      id: json['id'] as int?,
      motoboyId: json['motoboyId'] as int,
      turnoId: json['turnoId'] as int?,
      tipo: _parseTipo(json['tipo'] as String),
      valor: (json['valor'] as num).toDouble(),
      descricao: json['descricao'] as String,
      status: StatusTransacao.values
          .byName((json['status'] as String).toLowerCase()),
      criadoEm: DateTime.parse(json['criadoEm'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'motoboyId': motoboyId,
      if (turnoId != null) 'turnoId': turnoId,
      'tipo': tipo.name.toUpperCase(),
      'valor': valor,
      'descricao': descricao,
      'status': status.name.toUpperCase(),
      'criadoEm': criadoEm.toIso8601String(),
    };
  }

  bool get isCredito => tipo != TipoTransacao.saque;
}

enum TipoTransacao {
  turno,
  entrega,
  bonus,
  saque;

  String get label {
    return switch (this) {
      TipoTransacao.turno => 'Turno Concluído',
      TipoTransacao.entrega => 'Entrega Concluída',
      TipoTransacao.bonus => 'Bônus',
      TipoTransacao.saque => 'Transferência',
    };
  }
}

enum StatusTransacao {
  pendente,
  processado,
  concluido,
  estornado;

  String get label {
    return switch (this) {
      StatusTransacao.pendente => 'Pendente',
      StatusTransacao.processado => 'Processado',
      StatusTransacao.concluido => 'Concluído',
      StatusTransacao.estornado => 'Estornado',
    };
  }
}
