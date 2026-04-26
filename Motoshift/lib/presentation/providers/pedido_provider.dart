import 'package:flutter/foundation.dart';
import '../../domain/entities/pedido_entity.dart';
import '../../domain/repositories/i_pedido_repository.dart';

// ============================================================
// PRESENTATION LAYER — State manager de pedidos (RF02/RF03).
// ============================================================

class PedidoProvider extends ChangeNotifier {
  final IPedidoRepository _repo;

  PedidoProvider({required IPedidoRepository repo}) : _repo = repo;

  List<PedidoEntity> pedidosDisponiveis = [];
  List<PedidoEntity> meusPedidos = [];
  bool carregando = false;
  String? erro;

  Future<void> carregarDisponiveis() async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      pedidosDisponiveis = await _repo.listarDisponiveis();
    } on PedidoException catch (e) {
      erro = e.message;
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  Future<void> carregarPorCliente(int clienteId) async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      meusPedidos = await _repo.listarPorCliente(clienteId);
    } on PedidoException catch (e) {
      erro = e.message;
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  Future<void> carregarPorMotoboy(int motoboyId) async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      meusPedidos = await _repo.listarPorMotoboy(motoboyId);
    } on PedidoException catch (e) {
      erro = e.message;
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  Future<PedidoEntity?> criarPedido(PedidoEntity pedido) async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      final criado = await _repo.criarPedido(pedido);
      meusPedidos = [criado, ...meusPedidos];
      return criado;
    } on PedidoException catch (e) {
      erro = e.message;
      return null;
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  Future<bool> aceitarPedido(int pedidoId, int motoboyId) async {
    try {
      final atualizado = await _repo.aceitarPedido(pedidoId, motoboyId);
      pedidosDisponiveis.removeWhere((p) => p.id == pedidoId);
      meusPedidos = [atualizado, ...meusPedidos];
      notifyListeners();
      return true;
    } on PedidoException catch (e) {
      erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> finalizarPedido(int pedidoId) async {
    try {
      final atualizado = await _repo.finalizarPedido(pedidoId);
      _atualizarNaLista(atualizado);
      return true;
    } on PedidoException catch (e) {
      erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelarPedido(int pedidoId) async {
    try {
      final atualizado = await _repo.cancelarPedido(pedidoId);
      _atualizarNaLista(atualizado);
      return true;
    } on PedidoException catch (e) {
      erro = e.message;
      notifyListeners();
      return false;
    }
  }

  void _atualizarNaLista(PedidoEntity atualizado) {
    meusPedidos = meusPedidos
        .map((p) => p.id == atualizado.id ? atualizado : p)
        .toList();
    notifyListeners();
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }
}
