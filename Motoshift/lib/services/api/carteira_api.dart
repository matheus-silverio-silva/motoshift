import '../../models/carteira.dart';
import 'api_client.dart';

/// Carteira: saldo, extrato, saque, chave Pix e o gráfico de ganhos.
class CarteiraApi {
  final ApiClient _client;

  CarteiraApi(this._client);

  Future<Carteira> buscarCarteira(int motoboyId) async {
    final data = await _client.get('/carteira/$motoboyId');
    return Carteira.fromJson(data as Map<String, dynamic>);
  }

  Future<void> solicitarSaque(int motoboyId, double valor) async {
    await _client.post('/carteira/$motoboyId/saque', {'valor': valor});
  }

  Future<List<Map<String, dynamic>>> buscarGrafico(int motoboyId,
      {int meses = 6}) async {
    final list = await _client.get('/carteira/$motoboyId/grafico?meses=$meses')
        as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> atualizarPix(int motoboyId, String chavePix) async {
    await _client.put('/carteira/$motoboyId/pix', {'chavePix': chavePix});
  }
}
