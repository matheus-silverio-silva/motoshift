// ============================================================
// DOMAIN LAYER — Entidade do histórico de serviços (RF04).
// ============================================================

enum TipoServico {
  pedido,
  turno;

  String get label => switch (this) {
        TipoServico.pedido => 'Entrega',
        TipoServico.turno => 'Turno',
      };
}

enum StatusHistorico {
  concluido,
  cancelado,
  emAndamento;

  String get label => switch (this) {
        StatusHistorico.concluido => 'Concluído',
        StatusHistorico.cancelado => 'Cancelado',
        StatusHistorico.emAndamento => 'Em Andamento',
      };
}

class HistoricoItemEntity {
  final int id;
  final TipoServico tipoServico;
  final String titulo;
  final String descricao;
  final double valor;
  final StatusHistorico status;
  final DateTime data;
  final String? nomeContraparte;
  final String? fotoContraparte;

  const HistoricoItemEntity({
    required this.id,
    required this.tipoServico,
    required this.titulo,
    required this.descricao,
    required this.valor,
    required this.status,
    required this.data,
    this.nomeContraparte,
    this.fotoContraparte,
  });
}
