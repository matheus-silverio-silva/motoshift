import '../../models/turno.dart';
import 'api_client.dart';

/// Turnos: publicação, aceite, encerramento e as confirmações de pagamento.
///
/// `aceitarTurno` e as confirmações ainda recebem o id do entregador porque as
/// telas o passam; o backend o ignora e usa o do token — trocar o número na
/// chamada não muda mais quem age.
class TurnoApi {
  final ApiClient _client;

  TurnoApi(this._client);

  Future<List<Turno>> listarTurnosDisponiveis({DateTime? data}) async {
    final query =
        data != null ? '?data=${data.toIso8601String().substring(0, 10)}' : '';
    final list = await _client.get('/turnos/disponiveis$query') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Turno>> listarTurnosDisponiveisComFiltros({
    String? horarioInicio,
    String? horarioFim,
    int? diaSemana,
    double? raioMaxKm,
    String? dataInicio,
    String? dataFim,
    String? ordenarPor,
    double? lat,
    double? lng,
    double? raioKm,
  }) async {
    final params = <String, String>{};
    if (horarioInicio != null) params['horarioInicio'] = horarioInicio;
    if (horarioFim != null) params['horarioFim'] = horarioFim;
    if (diaSemana != null) params['diaSemana'] = diaSemana.toString();
    if (raioMaxKm != null) params['raioMaxKm'] = raioMaxKm.toString();
    if (dataInicio != null) params['dataInicio'] = dataInicio;
    if (dataFim != null) params['dataFim'] = dataFim;
    if (ordenarPor != null) params['ordenarPor'] = ordenarPor;
    // lat+lng+raioKm ligam o filtro por distância real; a resposta passa a
    // trazer distanciaKm em cada turno.
    if (lat != null) params['lat'] = lat.toString();
    if (lng != null) params['lng'] = lng.toString();
    if (raioKm != null) params['raioKm'] = raioKm.toString();

    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final list = await _client.get('/turnos/disponiveis$query') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Turno>> listarTurnosLojista(int lojistId) async {
    final list = await _client.get('/turnos?lojistId=$lojistId') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Turno>> listarMeusTurnos(int motoboyId) async {
    final list =
        await _client.get('/turnos?motoboyId=$motoboyId') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Turno> criarTurno(Turno turno) async {
    final data = await _client.post('/turnos', turno.toJson());
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> aceitarTurno(int turnoId, int motoboyId) async {
    final data =
        await _client.put('/turnos/$turnoId/aceitar', {'motoboyId': motoboyId});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> finalizarTurno(int turnoId) async {
    final data = await _client.put('/turnos/$turnoId/finalizar', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> cancelarTurno(int turnoId) async {
    final data = await _client.put('/turnos/$turnoId/cancelar', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> confirmarPagamentoLojista(int turnoId, int lojistaId,
      {int? motoboyId}) async {
    final data = await _client.put('/turnos/$turnoId/confirmar-pagamento-lojista', {
      'lojistaId': lojistaId,
      if (motoboyId != null) 'motoboyId': motoboyId,
    });
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> confirmarRecebimentoMotoboy(int turnoId, int motoboyId) async {
    final data = await _client.put(
        '/turnos/$turnoId/confirmar-recebimento-motoboy',
        {'motoboyId': motoboyId});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  /// Entregadores inscritos num turno multi-vaga, com status de pagamento.
  Future<List<Map<String, dynamic>>> listarInscritos(int turnoId) async {
    final list = await _client.get('/turnos/$turnoId/inscritos') as List<dynamic>;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
}
