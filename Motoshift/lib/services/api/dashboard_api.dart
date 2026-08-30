import 'api_client.dart';

/// Indicadores das telas iniciais dos dois perfis (RF02).
class DashboardApi {
  final ApiClient _client;

  DashboardApi(this._client);

  Future<Map<String, dynamic>> dashboardLojista(int lojistId) async {
    final data = await _client.get('/dashboard/lojista/$lojistId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) async {
    final data = await _client.get('/dashboard/motoboy/$motoboyId');
    return data as Map<String, dynamic>;
  }
}
