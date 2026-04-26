import '../../domain/entities/historico_item_entity.dart';
import '../../domain/repositories/i_historico_repository.dart';
import '../../services/api_service.dart';
import '../models/historico_item_model.dart';

// ============================================================
// DATA LAYER — Implementação de IHistoricoRepository (RF04).
// Endpoint: GET /api/historico/{usuarioId}
// ============================================================

class HistoricoRepositoryImpl implements IHistoricoRepository {
  final ApiService _api;

  HistoricoRepositoryImpl(this._api);

  @override
  Future<List<HistoricoItemEntity>> listarHistorico(
    int usuarioId, {
    TipoServico? tipoFiltro,
    int pagina = 0,
    int tamanhoPagina = 20,
  }) async {
    final params = StringBuffer('?pagina=$pagina&tamanho=$tamanhoPagina');
    if (tipoFiltro != null) {
      params.write('&tipo=${tipoFiltro.name.toUpperCase()}');
    }
    try {
      final list =
          await _api.rawGet('/historico/$usuarioId$params') as List<dynamic>;
      return list
          .map((e) => HistoricoItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw Exception('Erro ao carregar histórico: ${e.message}');
    }
  }
}
