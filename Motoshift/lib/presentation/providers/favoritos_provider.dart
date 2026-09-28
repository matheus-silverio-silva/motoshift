import 'package:flutter/foundation.dart';

import '../../models/entregador_favorito.dart';
import '../../services/api_service.dart';

/// Os entregadores favoritos do lojista logado (V18) — uma fonte só para o
/// coração do perfil público, do "Avaliar entregadores", do detalhe do turno
/// e da lista no perfil. Tocar o coração num lugar muda os outros.
///
/// Carrega sob demanda, na primeira vez que um coração aparece: o entregador
/// nunca chama a rota (o backend responderia 403), e o lojista que não abre
/// nenhuma dessas telas não paga a consulta.
class FavoritosProvider extends ChangeNotifier {
  FavoritosProvider(this._api);

  final ApiService _api;

  List<EntregadorFavorito> _lista = const [];
  bool _carregado = false;
  bool _carregando = false;
  int? _usuarioCarregado;
  String? _erro;
  final Set<int> _alterando = {};

  List<EntregadorFavorito> get lista => _lista;
  bool get carregado => _carregado;
  bool get carregando => _carregando;
  String? get erro => _erro;

  bool ehFavorito(int motoboyId) => _lista.any((f) => f.motoboyId == motoboyId);
  bool alterando(int motoboyId) => _alterando.contains(motoboyId);

  /// Carrega os favoritos de [usuarioId]. Outra conta no mesmo aparelho
  /// (sair e entrar como outra loja) recarrega do zero — os corações de uma
  /// loja não aparecem para a outra.
  Future<void> carregar(int? usuarioId, {bool forcar = false}) async {
    if (usuarioId == null) return;
    final outraConta = usuarioId != _usuarioCarregado;
    if (outraConta) {
      _lista = const [];
      _carregado = false;
    }
    if (_carregando || (_carregado && !forcar)) return;
    _usuarioCarregado = usuarioId;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _lista = await _api.favoritos.listar();
      _carregado = true;
    } on ApiException catch (e) {
      _erro = e.message;
    } catch (_) {
      _erro = 'Não foi possível carregar os favoritos.';
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Liga ou desliga o coração. Devolve a mensagem de erro, ou `null` se deu
  /// certo. O estado só muda depois da resposta: um coração que acende e
  /// apaga de novo quando a rede falha diz mais do que um que mente.
  Future<String?> alternar(int motoboyId) async {
    if (_alterando.contains(motoboyId)) return null;
    _alterando.add(motoboyId);
    notifyListeners();
    try {
      if (ehFavorito(motoboyId)) {
        await _api.favoritos.desfavoritar(motoboyId);
        _lista = _lista.where((f) => f.motoboyId != motoboyId).toList();
      } else {
        final novo = await _api.favoritos.favoritar(motoboyId);
        _lista = [novo, ..._lista.where((f) => f.motoboyId != motoboyId)];
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Não foi possível atualizar o favorito.';
    } finally {
      _alterando.remove(motoboyId);
      notifyListeners();
    }
  }

}
