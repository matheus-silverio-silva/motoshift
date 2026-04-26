import '../../domain/entities/pedido_entity.dart';

// ============================================================
// DATA LAYER — DTO com serialização JSON (RF02/RF03).
// Herda PedidoEntity e adiciona fromJson/toJson.
// ============================================================

class PedidoModel extends PedidoEntity {
  const PedidoModel({
    super.id,
    required super.clienteId,
    super.motoboyId,
    required super.enderecoOrigem,
    required super.enderecoDestino,
    super.referenciaOrigem,
    super.referenciaDestino,
    required super.tipoCarga,
    super.observacoes,
    super.status,
    super.valorEstimado,
    required super.criadoEm,
    super.atualizadoEm,
    super.nomeCliente,
    super.nomeMotoboy,
  });

  factory PedidoModel.fromJson(Map<String, dynamic> json) {
    return PedidoModel(
      id: json['id'] as int?,
      clienteId: json['clienteId'] as int,
      motoboyId: json['motoboyId'] as int?,
      enderecoOrigem: json['enderecoOrigem'] as String,
      enderecoDestino: json['enderecoDestino'] as String,
      referenciaOrigem: json['referenciaOrigem'] as String?,
      referenciaDestino: json['referenciaDestino'] as String?,
      tipoCarga: TipoCarga.values.byName(
        (json['tipoCarga'] as String).toLowerCase(),
      ),
      observacoes: json['observacoes'] as String?,
      status: StatusPedido.values.byName(
        _normalizeStatus(json['status'] as String),
      ),
      valorEstimado: json['valorEstimado'] != null
          ? (json['valorEstimado'] as num).toDouble()
          : null,
      criadoEm: DateTime.parse(json['criadoEm'] as String),
      atualizadoEm: json['atualizadoEm'] != null
          ? DateTime.parse(json['atualizadoEm'] as String)
          : null,
      nomeCliente: json['nomeCliente'] as String?,
      nomeMotoboy: json['nomeMotoboy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'clienteId': clienteId,
      if (motoboyId != null) 'motoboyId': motoboyId,
      'enderecoOrigem': enderecoOrigem,
      'enderecoDestino': enderecoDestino,
      if (referenciaOrigem != null) 'referenciaOrigem': referenciaOrigem,
      if (referenciaDestino != null) 'referenciaDestino': referenciaDestino,
      'tipoCarga': tipoCarga.name.toUpperCase(),
      if (observacoes != null) 'observacoes': observacoes,
      'status': status.name.toUpperCase(),
      if (valorEstimado != null) 'valorEstimado': valorEstimado,
    };
  }

  /// Converte EM_TRANSITO → emTransito para bater com o enum Dart.
  static String _normalizeStatus(String raw) {
    final parts = raw.toLowerCase().replaceAll('_', ' ').split(' ');
    return parts
        .indexed
        .map((e) => e.$1 == 0 ? e.$2 : e.$2[0].toUpperCase() + e.$2.substring(1))
        .join('');
  }
}
