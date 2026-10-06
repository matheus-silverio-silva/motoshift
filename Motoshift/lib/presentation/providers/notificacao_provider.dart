import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../models/notificacao.dart';
import '../../services/api_service.dart';

/// Notificações do usuário e a contagem que alimenta o badge do sino.
///
/// A contagem é carregada separadamente da lista porque o sino aparece em
/// telas que não abrem a central — buscar a lista inteira só para desenhar um
/// número seria desperdício.
///
/// <h3>O sino se atualiza sozinho</h3>
/// A contagem só era buscada quando um painel abria: o lojista ficava com a
/// tela aberta e não via "Ricardo chegou às 14:03" até trocar de tela. Agora,
/// enquanto há sessão, ela é buscada a cada [intervaloDaContagem] (45 s):
///
/// * [acompanharSessao] liga com o login (buscando na hora) e desliga com o
///   logout — quem chama é o `app.dart`, a cada mudança do `AuthService`;
/// * com o app em segundo plano o relógio para: ninguém está olhando o sino,
///   e no celular isso é bateria e dados. Ao voltar, busca na hora e o
///   relógio recomeça;
/// * `intervaloDaContagem: null` não cria relógio nenhum — é o que os testes
///   usam quando o polling não é o assunto.
///
/// É polling, e não push nem WebSocket, de propósito: uma requisição pequena
/// a cada 45 s resolve o caso sem infraestrutura nova no backend.
class NotificacaoProvider extends ChangeNotifier {
  NotificacaoProvider(
    this._api, {
    this.intervaloDaContagem = const Duration(seconds: 45),
  });

  final ApiService _api;

  /// De quanto em quanto tempo a contagem do sino é buscada enquanto há
  /// sessão. Nulo desliga o polling.
  final Duration? intervaloDaContagem;

  List<Notificacao> _notificacoes = [];
  int _naoLidas = 0;
  bool _carregando = false;
  String? _erro;

  Timer? _relogio;
  AppLifecycleListener? _cicloDeVida;
  int? _usuarioDaSessao;

  /// Sobe a cada login e logout: a resposta de uma busca que começou em outra
  /// sessão é descartada.
  int _trocasDeSessao = 0;
  bool _emSegundoPlano = false;
  bool _descartado = false;

  List<Notificacao> get notificacoes => _notificacoes;
  int get naoLidas => _naoLidas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// O relógio da contagem está correndo? Só para os testes.
  @visibleForTesting
  bool get acompanhando => _relogio?.isActive ?? false;

  List<Notificacao> porTipo(String? filtro) {
    if (filtro == null) return _notificacoes;
    if (filtro == 'naoLidas') {
      return _notificacoes.where((n) => !n.lida).toList();
    }
    return _notificacoes.where((n) => n.tipo.startsWith(filtro)).toList();
  }

  // ── O sino que se atualiza sozinho ───────────────────────────────────────

  /// Liga o polling para a sessão de [usuarioId], ou desliga com `null`.
  ///
  /// Chamado a cada mudança do `AuthService` — inclusive de dentro de um
  /// `build` —, então não notifica ninguém na hora: repetir o mesmo usuário
  /// não faz nada, e o que muda é avisado depois.
  void acompanharSessao(int? usuarioId) {
    if (usuarioId == _usuarioDaSessao) return;
    _usuarioDaSessao = usuarioId;
    _trocasDeSessao++;
    _pararRelogio();

    if (usuarioId == null) {
      // Logout: o que era da conta anterior não pode ficar no sino da próxima.
      _cicloDeVida?.dispose();
      _cicloDeVida = null;
      _notificacoes = [];
      _naoLidas = 0;
      scheduleMicrotask(_avisar);
      return;
    }

    _cicloDeVida ??= AppLifecycleListener(onStateChange: _aoMudarCicloDeVida);
    unawaited(carregarContagem(usuarioId));
    _ligarRelogio();
  }

  void _ligarRelogio() {
    _pararRelogio();
    final intervalo = intervaloDaContagem;
    final usuario = _usuarioDaSessao;
    if (intervalo == null || usuario == null || _emSegundoPlano) return;
    _relogio = Timer.periodic(intervalo, (_) => carregarContagem(usuario));
  }

  void _pararRelogio() {
    _relogio?.cancel();
    _relogio = null;
  }

  void _aoMudarCicloDeVida(AppLifecycleState estado) {
    switch (estado) {
      case AppLifecycleState.resumed:
        if (!_emSegundoPlano) return;
        _emSegundoPlano = false;
        final usuario = _usuarioDaSessao;
        if (usuario == null) return;
        // Voltou: o que chegou enquanto esteve fora aparece na hora, sem
        // esperar a próxima volta do relógio.
        unawaited(carregarContagem(usuario));
        _ligarRelogio();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _emSegundoPlano = true;
        _pararRelogio();
      case AppLifecycleState.inactive:
        // Perdeu o foco mas continua na tela (outra janela por cima, a
        // central de notificações do celular): o sino segue visível.
        break;
    }
  }

  void _avisar() {
    if (!_descartado) notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _pararRelogio();
    _cicloDeVida?.dispose();
    _cicloDeVida = null;
    super.dispose();
  }

  // ── Contagem e lista ─────────────────────────────────────────────────────

  Future<void> carregarContagem(int usuarioId) async {
    final sessao = _trocasDeSessao;
    try {
      final total =
          await _api.notificacoes.contarNotificacoesNaoLidas(usuarioId);
      // A resposta pode chegar depois do logout (ou de outro login): a conta
      // que perguntou já não é a que está na tela.
      if (_descartado || sessao != _trocasDeSessao) return;
      _naoLidas = total;
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
      final lista = await _api.notificacoes.listarNotificacoes(usuarioId);
      _notificacoes = lista.map(Notificacao.fromJson).toList()
        ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      _naoLidas = _notificacoes.where((n) => !n.lida).length;
    } on ApiException catch (e) {
      _erro = e.message;
    } catch (_) {
      _erro = 'Não foi possível carregar as notificações.';
    } finally {
      _carregando = false;
      _avisar();
    }
  }

  Future<void> marcarLida(int id) async {
    final i = _notificacoes.indexWhere((n) => n.id == id);
    if (i == -1 || _notificacoes[i].lida) return;
    try {
      await _api.notificacoes.marcarNotificacaoLida(id);
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
      _avisar();
    } catch (_) {
      // Mantém como não lida — o estado local não pode divergir do servidor.
    }
  }

  Future<void> marcarTodasLidas(int usuarioId) async {
    try {
      await _api.notificacoes.marcarTodasNotificacoesLidas(usuarioId);
      await carregar(usuarioId);
    } catch (_) {
      _erro = 'Não foi possível marcar todas como lidas.';
      _avisar();
    }
  }
}
