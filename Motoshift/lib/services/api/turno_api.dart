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

  /// Um turno pelo id — GET /api/turnos/{id}.
  ///
  /// A notificação carrega só o id do turno, e as telas de detalhe recebem o
  /// objeto por argumento de rota. Sem este método, tocar numa notificação de
  /// turno só podia marcá-la como lida: não havia como montar o destino.
  Future<Turno> buscarTurno(int turnoId) async {
    final data = await _client.get('/turnos/$turnoId');
    return Turno.fromJson(data as Map<String, dynamic>);
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

  /// Cancela o turno inteiro — só o lojista que o publicou. A reserva volta e
  /// nenhum entregador é penalizado; o entregador que chamar isto leva 403.
  Future<Turno> cancelarTurno(int turnoId) async {
    final data = await _client.put('/turnos/$turnoId/cancelar', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  /// O entregador desiste da vaga dele — e só dela: o turno segue, a vaga
  /// reabre e a loja é avisada. A menos de 1 h do início, custa 0,5 de score
  /// a quem desistiu. Recusado (409) depois do check-in.
  Future<Turno> desistirDaVaga(int turnoId) async {
    final data = await _client.put('/turnos/$turnoId/desistir', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  // confirmarPagamentoLojista e confirmarRecebimentoMotoboy sairam daqui.
  //
  // A dupla confirmacao deixou de existir: o lojista compromete o valor ao
  // publicar o turno e a finalizacao transfere o que ja estava reservado, na
  // mesma transacao. Nao ha o que declarar depois — e uma confirmacao que nao
  // decide nada so adiava o pagamento de quem trabalhou. As rotas
  // correspondentes tambem sairam do backend.

  /// "Cheguei" — o check-in do entregador (V16). O backend confere a janela
  /// (30 min antes do início até o fim) e a distância até o ponto do turno;
  /// sem posição, só passa com a trava de proximidade desligada.
  Future<Turno> checkin(int turnoId, {double? latitude, double? longitude}) async {
    final data = await _client.put('/turnos/$turnoId/checkin', {
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  /// "Encerrar turno" — o check-out. Não finaliza: finalizar é o que paga.
  Future<Turno> checkout(int turnoId) async {
    final data = await _client.put('/turnos/$turnoId/checkout', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  /// Gorjeta do lojista a um entregador do turno finalizado (V17). O backend
  /// confere quem dá, a quem, o teto e o saldo; repetir a mesma gorjeta não
  /// cobra de novo.
  Future<void> darGorjeta(int turnoId, int entregadorId, double valor) async {
    await _client.post('/turnos/$turnoId/gorjetas', {
      'entregadorId': entregadorId,
      'valor': valor,
    });
  }

  /// Entregadores inscritos num turno multi-vaga, com status de pagamento e,
  /// para o lojista e para o próprio entregador, a chegada e a saída.
  Future<List<Map<String, dynamic>>> listarInscritos(int turnoId) async {
    final list = await _client.get('/turnos/$turnoId/inscritos') as List<dynamic>;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
}
