import 'api_client.dart';

/// Calendário de turnos do usuário: mês e semana.
class AgendaApi {
  final ApiClient _client;

  AgendaApi(this._client);

  Future<Map<String, dynamic>> buscarAgendaMensal(
      int usuarioId, int mes, int ano) async {
    final data = await _client.get('/agenda/$usuarioId?mes=$mes&ano=$ano');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buscarAgendaSemanal(
      int usuarioId, String data) async {
    final d = await _client.get('/agenda/$usuarioId/semana?data=$data');
    return d as Map<String, dynamic>;
  }
}
