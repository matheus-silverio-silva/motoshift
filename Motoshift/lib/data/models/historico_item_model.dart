import '../../domain/entities/historico_item_entity.dart';

// ============================================================
// DATA LAYER — DTO para GET /api/historico/{id} (RF04).
// ============================================================

class HistoricoItemModel extends HistoricoItemEntity {
  const HistoricoItemModel({
    required super.id,
    required super.tipoServico,
    required super.titulo,
    required super.descricao,
    required super.valor,
    required super.status,
    required super.data,
    super.nomeContraparte,
    super.fotoContraparte,
  });

  factory HistoricoItemModel.fromJson(Map<String, dynamic> json) {
    return HistoricoItemModel(
      id: json['id'] as int,
      tipoServico: TipoServico.values.byName(
        (json['tipoServico'] as String).toLowerCase(),
      ),
      titulo: json['titulo'] as String,
      descricao: json['descricao'] as String,
      valor: (json['valor'] as num).toDouble(),
      status: StatusHistorico.values.byName(
        _normalizeStatus(json['status'] as String),
      ),
      data: DateTime.parse(json['data'] as String),
      nomeContraparte: json['nomeContraparte'] as String?,
      fotoContraparte: json['fotoContraparte'] as String?,
    );
  }

  static String _normalizeStatus(String raw) {
    final parts = raw.toLowerCase().replaceAll('_', ' ').split(' ');
    return parts
        .indexed
        .map((e) => e.$1 == 0 ? e.$2 : e.$2[0].toUpperCase() + e.$2.substring(1))
        .join('');
  }
}
