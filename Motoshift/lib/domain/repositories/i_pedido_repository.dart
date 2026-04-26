import '../entities/pedido_entity.dart';

// ============================================================
// DOMAIN LAYER — Contrato de pedidos de entrega (RF02/RF03).
// ============================================================

abstract interface class IPedidoRepository {
  Future<PedidoEntity> criarPedido(PedidoEntity pedido);
  Future<List<PedidoEntity>> listarDisponiveis();
  Future<List<PedidoEntity>> listarPorCliente(int clienteId);
  Future<List<PedidoEntity>> listarPorMotoboy(int motoboyId);
  Future<PedidoEntity> aceitarPedido(int pedidoId, int motoboyId);
  Future<PedidoEntity> finalizarPedido(int pedidoId);
  Future<PedidoEntity> cancelarPedido(int pedidoId);
}
