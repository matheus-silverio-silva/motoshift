import '../entities/historico_item_entity.dart';

// ============================================================
// DOMAIN LAYER — Contrato do histórico de serviços (RF04).
// ============================================================

abstract interface class IHistoricoRepository {
  Future<List<HistoricoItemEntity>> listarHistorico(
    int usuarioId, {
    TipoServico? tipoFiltro,
    int pagina = 0,
    int tamanhoPagina = 20,
  });
}
