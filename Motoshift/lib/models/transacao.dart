/// Tipos que o backend emite, em `Transacao.tipo`:
///   recarga | reserva | liberacao_reserva | pagamento_enviado
///   | pagamento_recebido | saque | bonus | estorno
/// ("turno" é o legado dos créditos anteriores à liquidação automática.)
///
/// O default caía em `TipoTransacao.turno`, que é crédito. Quando a liquidação
/// automática começar a emitir `reserva` e `pagamento_enviado` — que são saídas
/// da carteira do lojista — eles apareceriam no extrato como **entrada**, com
/// sinal de mais e cor de crédito. Daí o `desconhecido`: um tipo que este app
/// ainda não conhece não pode ser chutado para um dos lados.
TipoTransacao _parseTipo(String raw) {
  return switch (raw.toLowerCase()) {
    'turno' => TipoTransacao.turno,
    'entrega' => TipoTransacao.entrega,
    'bonus' => TipoTransacao.bonus,
    'saque' => TipoTransacao.saque,
    'recarga' => TipoTransacao.recarga,
    'reserva' => TipoTransacao.reserva,
    'liberacao_reserva' => TipoTransacao.liberacaoReserva,
    'pagamento_enviado' => TipoTransacao.pagamentoEnviado,
    'pagamento_recebido' => TipoTransacao.pagamentoRecebido,
    'estorno' => TipoTransacao.estorno,
    _ => TipoTransacao.desconhecido,
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
      // `usuarioId` é o campo real desde a etapa 2; `motoboyId` ficou como
      // espelho para o app antigo. Ler os dois, nessa ordem, e nunca fazer
      // `as int` direto: `null as int` lança TypeError e derruba a tela de
      // carteira inteira — não só esta linha do extrato.
      motoboyId: (json['usuarioId'] ?? json['motoboyId']) as int? ?? 0,
      turnoId: json['turnoId'] as int?,
      tipo: _parseTipo(json['tipo'] as String),
      valor: (json['valor'] as num).toDouble(),
      descricao: json['descricao'] as String,
      status: _parseStatus(json['status'] as String?),
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

  /// `true` entra, `false` sai, `null` tipo desconhecido — ver
  /// [TipoTransacao.credito]. Era `tipo != saque`, ou seja: tudo que não fosse
  /// saque contava como entrada.
  bool? get credito => tipo.credito;
}

enum TipoTransacao {
  turno,
  entrega,
  bonus,
  saque,
  recarga,
  reserva,
  liberacaoReserva,
  pagamentoEnviado,
  pagamentoRecebido,
  estorno,

  /// Tipo que o backend emitiu e este app ainda não conhece. Existe para o
  /// extrato não fingir saber a direção do dinheiro.
  desconhecido;

  String get label {
    return switch (this) {
      TipoTransacao.turno => 'Turno Concluído',
      TipoTransacao.entrega => 'Entrega Concluída',
      TipoTransacao.bonus => 'Bônus',
      TipoTransacao.saque => 'Transferência',
      TipoTransacao.recarga => 'Recarga',
      TipoTransacao.reserva => 'Reserva de turno',
      TipoTransacao.liberacaoReserva => 'Reserva liberada',
      TipoTransacao.pagamentoEnviado => 'Pagamento enviado',
      TipoTransacao.pagamentoRecebido => 'Pagamento recebido',
      TipoTransacao.estorno => 'Estorno',
      TipoTransacao.desconhecido => 'Lançamento',
    };
  }

  /// `true` entra dinheiro, `false` sai, `null` não dá para afirmar.
  ///
  /// Nulo em vez de um chute: o extrato mostra o valor sem sinal e em tom
  /// neutro, que é honesto, em vez de rotular como entrada algo que pode ser
  /// saída.
  bool? get credito => switch (this) {
        TipoTransacao.saque ||
        TipoTransacao.reserva ||
        TipoTransacao.pagamentoEnviado =>
          false,
        TipoTransacao.desconhecido => null,
        _ => true,
      };
}

/// O `byName` que estava aqui lançava `ArgumentError` em qualquer status fora
/// da lista — e a entidade do backend já documenta `falhou`, que nunca esteve
/// no enum. Um único lançamento assim no extrato derrubava a tela de carteira
/// inteira, não só aquela linha.
StatusTransacao _parseStatus(String? raw) {
  return switch (raw?.toLowerCase()) {
    'pendente' => StatusTransacao.pendente,
    'processado' => StatusTransacao.processado,
    'concluido' || 'concluído' => StatusTransacao.concluido,
    'estornado' => StatusTransacao.estornado,
    'falhou' => StatusTransacao.falhou,
    _ => StatusTransacao.pendente,
  };
}

enum StatusTransacao {
  pendente,
  processado,
  concluido,
  estornado,
  falhou;

  String get label {
    return switch (this) {
      StatusTransacao.pendente => 'Pendente',
      StatusTransacao.processado => 'Processado',
      StatusTransacao.concluido => 'Concluído',
      StatusTransacao.estornado => 'Estornado',
      StatusTransacao.falhou => 'Falhou',
    };
  }

  /// Dinheiro que já é do usuário — mesmo corte do `STATUS_LIQUIDADO` no
  /// CarteiraService.
  bool get liquidado =>
      this == StatusTransacao.processado || this == StatusTransacao.concluido;
}
