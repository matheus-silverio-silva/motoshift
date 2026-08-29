import 'api_client.dart';

/// Avaliação mútua e a reputação que ela alimenta.
class AvaliacaoApi {
  final ApiClient _client;

  AvaliacaoApi(this._client);

  /// Avaliações recebidas por alguém: média, distribuição por estrela e lista.
  /// É também o que a tela de perfil público mostra.
  Future<Map<String, dynamic>> buscarAvaliacoes(int usuarioId) async {
    final data = await _client.get('/avaliacoes/usuario/$usuarioId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registrarAvaliacao(
      Map<String, dynamic> body) async {
    final data = await _client.post('/avaliacoes', body);
    return data as Map<String, dynamic>;
  }

  /// Ids dos turnos em que o usuário já avaliou alguém.
  Future<List<int>> buscarTurnosAvaliados(int usuarioId) async {
    final data = await _client.get('/avaliacoes/feitas/$usuarioId');
    final ids = (data as Map<String, dynamic>)['turnoIds'] as List<dynamic>;
    return ids.cast<int>();
  }

  Future<bool> verificarPendente(int turnoId, int usuarioId) async {
    final data =
        await _client.get('/avaliacoes/turno/$turnoId/pendentes/$usuarioId');
    return (data as Map<String, dynamic>)['precisaAvaliar'] as bool;
  }

  /// Devolve `precisaAvaliar` e a lista `pendentes` de `{usuarioId, nome}` —
  /// um turno multi-vaga tem um pendente por entregador.
  Future<({bool precisaAvaliar, List<Map<String, dynamic>> pendentes})>
      buscarAvaliacoesPendentes(int turnoId, int usuarioId) async {
    final data = await _client
        .get('/avaliacoes/turno/$turnoId/pendentes/$usuarioId')
            as Map<String, dynamic>;
    final lista = (data['pendentes'] as List<dynamic>? ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return (
      precisaAvaliar: data['precisaAvaliar'] == true,
      pendentes: lista,
    );
  }
}
