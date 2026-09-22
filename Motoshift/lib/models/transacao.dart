import 'documento_fiscal.dart';

/// Tipos que o backend emite, em `Transacao.tipo`:
///   recarga | reserva | liberacao_reserva | pagamento_enviado
///   | pagamento_recebido | saque | bonus | estorno
///   | retencao_iss | retencao_irrf (só com a retenção na fonte ligada)
/// ("turno" é o legado dos créditos anteriores à liquidação automática.)
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
    'retencao_iss' => TipoTransacao.retencaoIss,
    'retencao_irrf' => TipoTransacao.retencaoIrrf,
    _ => TipoTransacao.desconhecido,
  };
}

/// De que lado o dinheiro anda, lido do backend em vez de adivinhado.
///
/// O app decidia o sinal de cada linha por uma lista de tipos conhecidos — e
/// um tipo que esta versão não conhecesse virava crédito por omissão. Uma
/// reserva de R$ 360 aparecia no extrato com sinal de mais e cor de entrada.
/// Agora o backend grava a direção junto com o lançamento e o app só desenha.
NaturezaTransacao? _parseNatureza(String? raw) {
  return switch (raw?.toLowerCase()) {
    'credito' => NaturezaTransacao.credito,
    'debito' => NaturezaTransacao.debito,
    // Lançamento antigo, de antes de o backend gravar a natureza: o extrato
    // mostra o valor em tom neutro em vez de chutar um lado.
    _ => null,
  };
}

enum NaturezaTransacao {
  credito,
  debito;

  bool get isCredito => this == NaturezaTransacao.credito;

  /// O prefixo do valor na tela: '+', '-' ou nada quando não se sabe.
  String get sinal => isCredito ? '+' : '-';
}

// Mapeado para a entidade `Transacao` no Spring Boot
// Tabela: transacoes
class Transacao {
  final int? id;
  final int motoboyId; // FK → usuarios.id (dono do lançamento)
  final int? contraparteId; // o outro lado, quando existe
  final int? turnoId; // FK → turnos.id (null em recarga, saque, bônus)
  final TipoTransacao tipo;

  /// Entrada ou saída. `null` só em lançamento anterior à V12.
  final NaturezaTransacao? natureza;

  final double valor;
  final String descricao;
  final StatusTransacao status;
  final DateTime criadoEm;

  /// Une os dois lados de uma transferência: o `pagamento_enviado` do lojista
  /// e o `pagamento_recebido` do entregador são o mesmo evento.
  final String? operacaoId;

  /// Saldo logo depois deste lançamento. `null` no histórico anterior à V12 —
  /// o saldo daquele instante não é reconstruível, e a tela diz isso em vez de
  /// mostrar um número inventado.
  final double? saldoDisponivelApos;
  final double? saldoBloqueadoApos;

  /// Se dá para gerar o documento deste lançamento agora — NFS-e para
  /// pagamento de turno, recibo ou comprovante para o resto. Falso para o que
  /// não concluiu e para saque com Pix ainda pendente.
  final bool documentoDisponivel;

  /// Que documento este lançamento gera; nulo quando não há.
  final TipoDocumento? tipoDocumento;

  /// Id da NFS-e, quando já emitida. Comprovante não tem: é derivado do
  /// lançamento a cada pedido.
  final int? documentoId;

  /// A NFS-e deste pagamento já foi gerada.
  bool get documentoEmitido => documentoId != null;

  const Transacao({
    this.id,
    required this.motoboyId,
    this.contraparteId,
    this.turnoId,
    required this.tipo,
    this.natureza,
    required this.valor,
    required this.descricao,
    this.status = StatusTransacao.concluido,
    required this.criadoEm,
    this.operacaoId,
    this.saldoDisponivelApos,
    this.saldoBloqueadoApos,
    this.documentoDisponivel = false,
    this.tipoDocumento,
    this.documentoId,
  });

  factory Transacao.fromJson(Map<String, dynamic> json) {
    return Transacao(
      id: json['id'] as int?,
      // `usuarioId` é o campo real desde a etapa 2; `motoboyId` ficou como
      // espelho para o app antigo. Ler os dois, nessa ordem, e nunca fazer
      // `as int` direto: `null as int` lança TypeError e derruba a tela de
      // carteira inteira — não só esta linha do extrato.
      motoboyId: (json['usuarioId'] ?? json['motoboyId']) as int? ?? 0,
      contraparteId: json['contraparteId'] as int?,
      turnoId: json['turnoId'] as int?,
      tipo: _parseTipo(json['tipo'] as String),
      natureza: _parseNatureza(json['natureza'] as String?),
      valor: (json['valor'] as num).toDouble(),
      descricao: json['descricao'] as String? ?? '',
      status: _parseStatus(json['status'] as String?),
      criadoEm: DateTime.parse(json['criadoEm'] as String),
      operacaoId: json['operacaoId'] as String?,
      saldoDisponivelApos: (json['saldoDisponivelApos'] as num?)?.toDouble(),
      saldoBloqueadoApos: (json['saldoBloqueadoApos'] as num?)?.toDouble(),
      documentoDisponivel: json['documentoDisponivel'] == true,
      tipoDocumento: TipoDocumento.parse(json['tipoDocumento'] as String?),
      documentoId: (json['documentoId'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'motoboyId': motoboyId,
      if (contraparteId != null) 'contraparteId': contraparteId,
      if (turnoId != null) 'turnoId': turnoId,
      'tipo': tipo.name.toUpperCase(),
      if (natureza != null) 'natureza': natureza!.name,
      'valor': valor,
      'descricao': descricao,
      'status': status.name.toUpperCase(),
      'criadoEm': criadoEm.toIso8601String(),
    };
  }

  /// `true` entra, `false` sai, `null` não dá para afirmar.
  ///
  /// Vem da coluna `natureza`, gravada pelo backend. Só cai no tipo quando o
  /// lançamento é anterior à V12 e não tem natureza — histórico, não fluxo novo.
  bool? get credito => natureza != null ? natureza!.isCredito : tipo.credito;

  /// O turno a que este lançamento pertence, quando há um.
  bool get temTurno => turnoId != null;
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

  /// ISS e IRRF retidos na fonte sobre um pagamento recebido — só existem com
  /// `motoshift.fiscal.reter-na-fonte=true` no backend.
  retencaoIss,
  retencaoIrrf,

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
      TipoTransacao.retencaoIss => 'ISS retido na fonte',
      TipoTransacao.retencaoIrrf => 'IRRF retido na fonte',
      TipoTransacao.desconhecido => 'Lançamento',
    };
  }

  /// O valor que a API espera na query string do filtro.
  String get valorApi {
    return switch (this) {
      TipoTransacao.liberacaoReserva => 'liberacao_reserva',
      TipoTransacao.pagamentoEnviado => 'pagamento_enviado',
      TipoTransacao.pagamentoRecebido => 'pagamento_recebido',
      TipoTransacao.retencaoIss => 'retencao_iss',
      TipoTransacao.retencaoIrrf => 'retencao_irrf',
      _ => name,
    };
  }

  /// Os tipos que o filtro do extrato oferece, na ordem em que fazem sentido
  /// para quem lê: primeiro o dinheiro que entra e sai de verdade, depois os
  /// movimentos internos da carteira.
  static List<TipoTransacao> get filtraveis => const [
        TipoTransacao.recarga,
        TipoTransacao.pagamentoRecebido,
        TipoTransacao.pagamentoEnviado,
        TipoTransacao.saque,
        TipoTransacao.reserva,
        TipoTransacao.liberacaoReserva,
        TipoTransacao.estorno,
      ];

  /// Só para lançamento sem `natureza` — ver [Transacao.credito].
  bool? get credito => switch (this) {
        TipoTransacao.saque ||
        TipoTransacao.reserva ||
        TipoTransacao.pagamentoEnviado ||
        TipoTransacao.retencaoIss ||
        TipoTransacao.retencaoIrrf =>
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

  /// Dinheiro que já é do usuário — mesmo corte que o backend usa ao somar.
  bool get liquidado =>
      this == StatusTransacao.processado || this == StatusTransacao.concluido;
}
