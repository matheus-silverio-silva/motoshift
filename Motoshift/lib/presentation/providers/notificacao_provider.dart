import 'package:flutter/foundation.dart';
import '../../models/notificacao.dart';
import '../../services/api_service.dart';

/// Notificações do usuário e a contagem que alimenta o badge do sino.
///
/// A contagem é carregada separadamente da lista porque o sino aparece em
/// telas que não abrem a central — buscar a lista inteira só para desenhar um
/// número seria desperdício.
class NotificacaoProvider extends ChangeNotifier {
  NotificacaoProvider(this._api);

  final ApiService _api;

  List<Notificacao> _notificacoes = [];
  int _naoLidas = 0;
  bool _carregando = false;
  String? _erro;

  List<Notificacao> get notificacoes => _notificacoes;
  int get naoLidas => _naoLidas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  List<Notificacao> porTipo(String? filtro) {
    if (filtro == null) return _notificacoes;
    if (filtro == 'naoLidas') {
      return _notificacoes.where((n) => !n.lida).toList();
    }
    return _notificacoes.where((n) => n.tipo.startsWith(filtro)).toList();
  }

  Future<void> carregarContagem(int usuarioId) async {
    try {
      _naoLidas = await _api.contarNotificacoesNaoLidas(usuarioId);
      notifyListeners();
    } catch (_) {
      // O badge é informação secundária: falhar aqui não pode quebrar a tela
      // que só queria desenhar o sino.
    }
  }

  Future<void> carregar(int usuarioId) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final lista = await _api.listarNotificacoes(usuarioId);
      _notificacoes = lista.map(Notificacao.fromJson).toList()
        ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      _naoLidas = _notificacoes.where((n) => !n.lida).length;
    } on ApiException catch (e) {
      _erro = e.message;
    } catch (_) {
      _erro = 'Não foi possível carregar as notificações.';
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> marcarLida(int id) async {
    final i = _notificacoes.indexWhere((n) => n.id == id);
    if (i == -1 || _notificacoes[i].lida) return;
    try {
      await _api.marcarNotificacaoLida(id);
      _notificacoes[i] = Notificacao(
        id: _notificacoes[i].id,
        tipo: _notificacoes[i].tipo,
        titulo: _notificacoes[i].titulo,
        mensagem: _notificacoes[i].mensagem,
        lida: true,
        criadoEm: _notificacoes[i].criadoEm,
        referenciaTipo: _notificacoes[i].referenciaTipo,
        referenciaId: _notificacoes[i].referenciaId,
      );
      _naoLidas = _notificacoes.where((n) => !n.lida).length;
      notifyListeners();
    } catch (_) {
      // Mantém como não lida — o estado local não pode divergir do servidor.
    }
  }

  Future<void> marcarTodasLidas(int usuarioId) async {
    try {
      await _api.marcarTodasNotificacoesLidas(usuarioId);
      await carregar(usuarioId);
    } catch (_) {
      _erro = 'Não foi possível marcar todas como lidas.';
      notifyListeners();
    }
  }
}
