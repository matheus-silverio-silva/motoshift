import '../../domain/entities/pedido_entity.dart';
import '../../domain/repositories/i_pedido_repository.dart';
import '../../services/api_service.dart';
import '../models/pedido_model.dart';

// ============================================================
// DATA LAYER — Implementação de IPedidoRepository (RF02/RF03).
// ============================================================

class PedidoRepositoryImpl implements IPedidoRepository {
  final ApiService _api;

  PedidoRepositoryImpl(this._api);

  @override
  Future<PedidoEntity> criarPedido(PedidoEntity pedido) async {
    try {
      final model = _toModel(pedido);
      final data = await _api.rawPost('/pedidos', model.toJson());
      return PedidoModel.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  @override
  Future<List<PedidoEntity>> listarDisponiveis() async {
    try {
      final list = await _api.rawGet('/pedidos/disponiveis') as List<dynamic>;
      return list
          .map((e) => PedidoModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  @override
  Future<List<PedidoEntity>> listarPorCliente(int clienteId) async {
    try {
      final list =
          await _api.rawGet('/pedidos?clienteId=$clienteId') as List<dynamic>;
      return list
          .map((e) => PedidoModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  @override
  Future<List<PedidoEntity>> listarPorMotoboy(int motoboyId) async {
    try {
      final list =
          await _api.rawGet('/pedidos?motoboyId=$motoboyId') as List<dynamic>;
      return list
          .map((e) => PedidoModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  @override
  Future<PedidoEntity> aceitarPedido(int pedidoId, int motoboyId) async {
    try {
      final data = await _api.rawPut(
        '/pedidos/$pedidoId/aceitar',
        {'motoboyId': motoboyId},
      );
      return PedidoModel.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  @override
  Future<PedidoEntity> finalizarPedido(int pedidoId) async {
    try {
      final data = await _api.rawPut('/pedidos/$pedidoId/finalizar', {});
      return PedidoModel.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  @override
  Future<PedidoEntity> cancelarPedido(int pedidoId) async {
    try {
      final data = await _api.rawPut('/pedidos/$pedidoId/cancelar', {});
      return PedidoModel.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PedidoException(e.message);
    }
  }

  PedidoModel _toModel(PedidoEntity p) => p is PedidoModel
      ? p
      : PedidoModel(
          id: p.id,
          clienteId: p.clienteId,
          motoboyId: p.motoboyId,
          enderecoOrigem: p.enderecoOrigem,
          enderecoDestino: p.enderecoDestino,
          referenciaOrigem: p.referenciaOrigem,
          referenciaDestino: p.referenciaDestino,
          tipoCarga: p.tipoCarga,
          observacoes: p.observacoes,
          status: p.status,
          valorEstimado: p.valorEstimado,
          criadoEm: p.criadoEm,
          atualizadoEm: p.atualizadoEm,
        );
}
