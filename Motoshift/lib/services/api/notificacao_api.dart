import 'api_client.dart';

/// Notificações in-app (RF09 / SCRUM-20): lista, badge do sino e leitura.
class NotificacaoApi {
  final ApiClient _client;

  NotificacaoApi(this._client);

  /// Cada item traz id, tipo, titulo, mensagem, referenciaTipo, referenciaId,
  /// lida e criadoEm.
  Future<List<Map<String, dynamic>>> listarNotificacoes(
    int usuarioId, {
    bool apenasNaoLidas = false,
  }) async {
    final query = '/notificacoes?usuarioId=$usuarioId'
        '${apenasNaoLidas ? '&apenasNaoLidas=true' : ''}';
    final list = await _client.get(query) as List<dynamic>;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Contagem de não lidas — alimenta o badge do sino.
  Future<int> contarNotificacoesNaoLidas(int usuarioId) async {
    final data = await _client.get('/notificacoes/contagem?usuarioId=$usuarioId')
        as Map<String, dynamic>;
    return (data['naoLidas'] as num?)?.toInt() ?? 0;
  }

  Future<void> marcarNotificacaoLida(int id) async {
    await _client.put('/notificacoes/$id/lida', const {});
  }

  Future<int> marcarTodasNotificacoesLidas(int usuarioId) async {
    final data = await _client.put(
        '/notificacoes/marcar-todas-lidas?usuarioId=$usuarioId', const {});
    return ((data as Map)['atualizadas'] as num?)?.toInt() ?? 0;
  }
}
