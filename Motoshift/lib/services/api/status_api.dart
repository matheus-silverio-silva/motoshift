import 'api_client.dart';

/// `GET /api/status`: o servidor está acordado? (SCRUM-48)
class StatusApi {
  final ApiClient _client;

  StatusApi(this._client);

  /// `true` quando o backend respondeu. Não lança: servidor dormindo, sem
  /// rede e tempo esgotado são todos "ainda não".
  Future<bool> noAr() => _client.servidorResponde();
}
