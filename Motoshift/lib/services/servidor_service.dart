import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Em que pé está a conversa com o backend.
enum EstadoDoServidor {
  /// Perguntando, ainda dentro do tempo normal de resposta. A tela não mostra
  /// nada: quase sempre a resposta chega antes de alguém notar.
  verificando,

  /// Passou do tempo normal: o servidor está acordando. A tela avisa.
  acordando,

  /// Respondeu.
  noAr,

  /// Passou do limite sem resposta. A tela oferece "Tentar novamente".
  semResposta,
}

/// Espera o servidor acordar (SCRUM-48).
///
/// No plano gratuito do Render o backend dorme depois de 15 minutos sem
/// requisição e leva minutos para acordar; as chamadas do app desistem em
/// 20 segundos. Sem isto, o primeiro login depois de um tempo parado falhava
/// sempre, com "Sem conexão com o servidor" — e quem tinha sessão salva era
/// mandado de volta ao login.
///
/// Ao abrir, o app pergunta `/api/status`. Se a resposta não vem em
/// [avisarApos], o estado vira [EstadoDoServidor.acordando] e uma nova
/// pergunta sai a cada [intervalo], até [limite]. A primeira que responder
/// encerra a espera — inclusive uma das antigas, que continuam valendo até o
/// tempo esgotado da própria requisição.
class ServidorService extends ChangeNotifier {
  ServidorService(
    this._api, {
    this.avisarApos = const Duration(seconds: 3),
    this.intervalo = const Duration(seconds: 5),
    this.limite = const Duration(minutes: 4),
    this.validade = const Duration(minutes: 10),
  });

  final ApiService _api;

  /// Quanto esperar a primeira resposta antes de avisar que o servidor está
  /// acordando.
  final Duration avisarApos;

  /// De quanto em quanto tempo perguntar de novo.
  final Duration intervalo;

  /// Quando desistir e mostrar o erro.
  final Duration limite;

  /// Por quanto tempo uma resposta vale. O servidor só dorme depois de 15
  /// minutos parado: dentro disto, voltar à tela de login não pergunta de novo.
  final Duration validade;

  EstadoDoServidor _estado = EstadoDoServidor.verificando;
  Future<bool>? _emAndamento;
  DateTime? _respondeuEm;
  Timer? _espera;
  Completer<void>? _fimDaEspera;
  bool _descartado = false;

  EstadoDoServidor get estado => _estado;
  bool get acordando => _estado == EstadoDoServidor.acordando;
  bool get semResposta => _estado == EstadoDoServidor.semResposta;

  /// Pergunta ao servidor se ele está no ar e insiste até ele responder.
  ///
  /// Completa com `true` quando respondeu e `false` quando o [limite] passou.
  /// Chamadas simultâneas dividem a mesma espera; chamar de novo depois de um
  /// `false` é o "Tentar novamente".
  Future<bool> aguardar() {
    final respondeuEm = _respondeuEm;
    if (_estado == EstadoDoServidor.noAr &&
        respondeuEm != null &&
        clock.now().difference(respondeuEm) < validade) {
      return Future.value(true);
    }
    return _emAndamento ??=
        _insistir().whenComplete(() => _emAndamento = null);
  }

  Future<bool> _insistir() async {
    _mudar(EstadoDoServidor.verificando);

    final respondeu = Completer<void>();
    void perguntar() {
      _api.status.noAr().then((ok) {
        if (ok && !respondeu.isCompleted) respondeu.complete();
      }, onError: (_) {});
    }

    var decorrido = Duration.zero;
    var espera = avisarApos;
    while (!_descartado) {
      perguntar();
      await Future.any([respondeu.future, _esperar(espera)]);
      if (_descartado) break;
      if (respondeu.isCompleted) {
        _cancelarEspera();
        _respondeuEm = clock.now();
        _mudar(EstadoDoServidor.noAr);
        return true;
      }
      decorrido += espera;
      if (decorrido >= limite) {
        _mudar(EstadoDoServidor.semResposta);
        return false;
      }
      _mudar(EstadoDoServidor.acordando);
      espera = intervalo;
    }
    return false;
  }

  /// Um intervalo que dá para cancelar: quando o servidor responde (ou a tela
  /// some), não sobra timer pendurado.
  Future<void> _esperar(Duration duracao) {
    final fim = Completer<void>();
    _fimDaEspera = fim;
    _espera = Timer(duracao, () {
      if (!fim.isCompleted) fim.complete();
    });
    return fim.future;
  }

  void _cancelarEspera() {
    _espera?.cancel();
    _espera = null;
    final fim = _fimDaEspera;
    _fimDaEspera = null;
    if (fim != null && !fim.isCompleted) fim.complete();
  }

  void _mudar(EstadoDoServidor novo) {
    if (_descartado || _estado == novo) return;
    _estado = novo;
    notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _cancelarEspera();
    super.dispose();
  }
}
