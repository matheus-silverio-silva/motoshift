// ============================================================
// DOMAIN LAYER — Entidade de Pedido de Entrega (RF02/RF03).
// ============================================================

enum TipoCarga {
  documentos,
  pequeno,
  medio,
  grande,
  fragil,
  perecivel;

  String get label => switch (this) {
        TipoCarga.documentos => 'Documentos',
        TipoCarga.pequeno => 'Pequeno',
        TipoCarga.medio => 'Médio',
        TipoCarga.grande => 'Grande',
        TipoCarga.fragil => 'Frágil',
        TipoCarga.perecivel => 'Perecível',
      };

  String get icon => switch (this) {
        TipoCarga.documentos => '📄',
        TipoCarga.pequeno => '📦',
        TipoCarga.medio => '📦',
        TipoCarga.grande => '🚛',
        TipoCarga.fragil => '🔮',
        TipoCarga.perecivel => '🌡',
      };
}

enum StatusPedido {
  aguardando,
  aceito,
  emTransito,
  entregue,
  cancelado;

  bool get isTerminal =>
      this == StatusPedido.entregue || this == StatusPedido.cancelado;

  String get label => switch (this) {
        StatusPedido.aguardando => 'Aguardando',
        StatusPedido.aceito => 'Aceito',
        StatusPedido.emTransito => 'Em Trânsito',
        StatusPedido.entregue => 'Entregue',
        StatusPedido.cancelado => 'Cancelado',
      };
}

class PedidoEntity {
  final int? id;
  final int clienteId;
  final int? motoboyId;
  final String enderecoOrigem;
  final String enderecoDestino;
  final String? referenciaOrigem;
  final String? referenciaDestino;
  final TipoCarga tipoCarga;
  final String? observacoes;
  final StatusPedido status;
  final double? valorEstimado;
  final DateTime criadoEm;
  final DateTime? atualizadoEm;
  final String? nomeCliente;
  final String? nomeMotoboy;

  const PedidoEntity({
    this.id,
    required this.clienteId,
    this.motoboyId,
    required this.enderecoOrigem,
    required this.enderecoDestino,
    this.referenciaOrigem,
    this.referenciaDestino,
    required this.tipoCarga,
    this.observacoes,
    this.status = StatusPedido.aguardando,
    this.valorEstimado,
    required this.criadoEm,
    this.atualizadoEm,
    this.nomeCliente,
    this.nomeMotoboy,
  });
}

class PedidoException implements Exception {
  final String message;
  const PedidoException(this.message);

  @override
  String toString() => 'PedidoException: $message';
}
