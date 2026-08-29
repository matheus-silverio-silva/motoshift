import 'api_client.dart';

/// Os três endpoints que passam pelo Claude: sugestão de turnos, relatório
/// mensal e análise de score.
///
/// Ficam juntos porque compartilham o mesmo risco: são chamadas a um serviço
/// externo, respondem 503 quando ele cai e nenhuma tela pode depender delas
/// para funcionar.
class IaApi {
  final ApiClient _client;

  IaApi(this._client);

  Future<String> buscarSugestoesTurnos(int motoboyId) async {
    final data = await _client.get('/sugestoes/turnos/$motoboyId');
    return (data as Map<String, dynamic>)['sugestoes'] as String;
  }

  Future<Map<String, dynamic>> buscarRelatorioMotoboy(int motoboyId) async {
    final data = await _client.get('/relatorio/motoboy/$motoboyId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buscarRelatorioLojista(int lojistaId) async {
    final data = await _client.get('/relatorio/lojista/$lojistaId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buscarAnaliseScore(int motoboyId) async {
    final data = await _client.get('/score/$motoboyId/analise');
    return data as Map<String, dynamic>;
  }
}
