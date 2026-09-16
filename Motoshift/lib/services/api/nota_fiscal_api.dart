import '../../models/nota_fiscal.dart';
import 'api_client.dart';

/// Notas fiscais de serviço dos turnos.
///
/// Nenhum método recebe o id do usuário: o backend o lê do token. A mesma
/// chamada serve ao lojista e ao entregador — muda o lado em que cada um
/// aparece no documento, não a rota.
class NotaFiscalApi {
  final ApiClient _client;

  NotaFiscalApi(this._client);

  /// Notas em que o usuário é prestador ou tomador, da mais recente à mais
  /// antiga.
  Future<List<NotaFiscal>> listar() async {
    final list = await _client.get('/notas-fiscais') as List<dynamic>;
    return list
        .map((e) => NotaFiscal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Turnos finalizados que ainda não geraram nota.
  Future<List<NotaFiscalPendente>> pendentes() async {
    final list = await _client.get('/notas-fiscais/pendentes') as List<dynamic>;
    return list
        .map((e) => NotaFiscalPendente.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Emite a nota do turno. [prestadorId] só é necessário quando quem emite é
  /// o lojista de um turno com mais de um entregador.
  Future<NotaFiscal> emitir(int turnoId, {int? prestadorId}) async {
    final data = await _client.post('/notas-fiscais', {
      'turnoId': turnoId,
      if (prestadorId != null) 'prestadorId': prestadorId,
    });
    return NotaFiscal.fromJson(data as Map<String, dynamic>);
  }

  Future<NotaFiscal> buscar(int id) async {
    final data = await _client.get('/notas-fiscais/$id');
    return NotaFiscal.fromJson(data as Map<String, dynamic>);
  }

  /// Cancelamento é do prestador; o backend recusa o pedido do tomador.
  Future<NotaFiscal> cancelar(int id, {String? motivo}) async {
    final data = await _client.put('/notas-fiscais/$id/cancelar', {
      if (motivo != null) 'motivo': motivo,
    });
    return NotaFiscal.fromJson(data as Map<String, dynamic>);
  }
}
