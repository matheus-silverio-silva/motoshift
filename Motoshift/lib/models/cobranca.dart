/// Uma recarga ou um saque no gateway.
///
/// Mapeado para `CobrancaResponse`. O ciclo de vida é o que interessa à tela:
/// a recarga nasce [StatusCobranca.pendente] esperando o Pix ser pago, e o
/// saque nasce pendente esperando o banco responder.
class Cobranca {
  final int id;
  final TipoCobranca tipo;
  final double valor;
  final StatusCobranca status;

  /// Copia-e-cola numa recarga; chave de destino num saque.
  final String? codigoPix;

  final DateTime criadaEm;
  final DateTime? concluidaEm;

  const Cobranca({
    required this.id,
    required this.tipo,
    required this.valor,
    required this.status,
    this.codigoPix,
    required this.criadaEm,
    this.concluidaEm,
  });

  factory Cobranca.fromJson(Map<String, dynamic> json) {
    return Cobranca(
      id: json['id'] as int,
      tipo: _parseTipo(json['tipo'] as String?),
      valor: (json['valor'] as num).toDouble(),
      status: _parseStatus(json['status'] as String?),
      codigoPix: json['codigoPix'] as String?,
      criadaEm: DateTime.parse(json['criadaEm'] as String),
      concluidaEm: json['concluidaEm'] != null
          ? DateTime.parse(json['concluidaEm'] as String)
          : null,
    );
  }

  bool get aguardandoPagamento => status == StatusCobranca.pendente;
}

enum TipoCobranca {
  recarga,
  saque;

  String get label => this == TipoCobranca.recarga ? 'Recarga' : 'Saque';
}

enum StatusCobranca {
  pendente,
  concluido,
  falhou;

  String get label {
    return switch (this) {
      StatusCobranca.pendente => 'Aguardando',
      StatusCobranca.concluido => 'Concluído',
      StatusCobranca.falhou => 'Recusado',
    };
  }
}

TipoCobranca _parseTipo(String? raw) =>
    raw == 'saque' ? TipoCobranca.saque : TipoCobranca.recarga;

/// Status desconhecido cai em pendente, nunca em erro: uma cobrança que o app
/// não sabe classificar não pode derrubar a tela de carteira.
StatusCobranca _parseStatus(String? raw) {
  return switch (raw?.toLowerCase()) {
    'concluido' || 'concluído' => StatusCobranca.concluido,
    'falhou' => StatusCobranca.falhou,
    _ => StatusCobranca.pendente,
  };
}
