import 'package:flutter/foundation.dart';
import '../../domain/entities/historico_item_entity.dart';
import '../../domain/repositories/i_historico_repository.dart';

// ============================================================
// PRESENTATION LAYER — State manager do histórico (RF04).
// ============================================================

class HistoricoProvider extends ChangeNotifier {
  final IHistoricoRepository _repo;

  HistoricoProvider({required IHistoricoRepository repo}) : _repo = repo;

  List<HistoricoItemEntity> itens = [];
  TipoServico? filtroAtivo;
  bool carregando = false;
  String? erro;
  int _pagina = 0;
  bool temMais = true;

  Future<void> carregar(int usuarioId, {bool resetar = true}) async {
    if (resetar) {
      _pagina = 0;
      itens = [];
      temMais = true;
    }
    if (!temMais) return;

    carregando = true;
    erro = null;
    notifyListeners();

    try {
      final novos = await _repo.listarHistorico(
        usuarioId,
        tipoFiltro: filtroAtivo,
        pagina: _pagina,
      );
      itens = resetar ? novos : [...itens, ...novos];
      temMais = novos.length == 20;
      _pagina++;
    } catch (e) {
      erro = e.toString();
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  void setFiltro(TipoServico? tipo, int usuarioId) {
    filtroAtivo = tipo;
    carregar(usuarioId);
  }

  void limparErro() {
    erro = null;
    notifyListeners();
  }
}
