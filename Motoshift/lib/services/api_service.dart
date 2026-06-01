import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;
import '../models/usuario.dart';
import '../models/turno.dart';
import '../models/transacao.dart';
import '../models/carteira.dart';

// ============================================================
// ApiService — Comunicação com o backend Java Spring Boot
// Base URL deve apontar para o servidor REST (localhost em dev)
// Troque para a URL de produção no ambiente adequado.
// ============================================================

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  // API_URL é injetada em build de produção via --dart-define=API_URL=https://...
  // Em dev: usa 10.0.2.2:8080 no emulador Android ou 127.0.0.1:8080 nas demais plataformas.
  static const String _apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

  static String get _baseUrl {
    if (_apiUrl.isNotEmpty) return '$_apiUrl/api';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    return 'http://localhost:8080/api';
  }

  String? _authToken;

  void setAuthToken(String token) => _authToken = token;
  void clearAuthToken() => _authToken = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  // --------------------------------------------------------
  // Métodos internos de request
  // --------------------------------------------------------

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = await http.get(uri, headers: _headers);
    } catch (_) {
      throw const ApiException(0, 'Sem conexao com o servidor');
    }
    return _handleResponse(response);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (_) {
      throw const ApiException(0, 'Sem conexao com o servidor');
    }
    return _handleResponse(response);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (_) {
      throw const ApiException(0, 'Sem conexao com o servidor');
    }
    return _handleResponse(response);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode >= 500) {
      throw ApiException(response.statusCode, 'Erro interno, tente novamente');
    }
    final body = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : <String, dynamic>{};
    final message = body['message'] ?? body['error'] ?? 'Erro desconhecido';
    throw ApiException(response.statusCode, message.toString());
  }

  // --------------------------------------------------------
  // Acesso HTTP público para repositórios (Clean Architecture)
  // --------------------------------------------------------

  Future<dynamic> rawGet(String path) => _get(path);
  Future<dynamic> rawPost(String path, Map<String, dynamic> body) => _post(path, body);
  Future<dynamic> rawPut(String path, Map<String, dynamic> body) => _put(path, body);

  // --------------------------------------------------------
  // AUTH — POST /api/auth/login | /api/auth/registro
  // --------------------------------------------------------

  Future<Map<String, dynamic>> login({
    required String email,
    required String senha,
    required TipoUsuario tipo,
  }) async {
    final data = await _post('/auth/login', {
      'email': email,
      'senha': senha,
      'tipo': tipo.name.toUpperCase(),
    });
    _authToken = data['token'] as String;
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registrar(Usuario usuario, String senha) async {
    final body = usuario.toJson()..['senha'] = senha;
    final data = await _post('/auth/registro', body);
    _authToken = data['token'] as String;
    return data as Map<String, dynamic>;
  }

  // --------------------------------------------------------
  // USUARIOS — GET /api/usuarios/{id}
  // --------------------------------------------------------

  Future<Usuario> buscarUsuario(int id) async {
    final data = await _get('/usuarios/$id');
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Usuario> atualizarUsuario(Usuario usuario) async {
    final data = await _put('/usuarios/${usuario.id}', usuario.toJson());
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Usuario> atualizarPerfil(int id, Map<String, dynamic> campos) async {
    final data = await _put('/usuarios/$id', campos);
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  // --------------------------------------------------------
  // TURNOS — /api/turnos
  // --------------------------------------------------------

  Future<List<Turno>> listarTurnosDisponiveis({DateTime? data}) async {
    final query = data != null
        ? '?data=${data.toIso8601String().substring(0, 10)}'
        : '';
    final list = await _get('/turnos/disponiveis$query') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Turno>> listarTurnosLojista(int lojistId) async {
    final list = await _get('/turnos?lojistId=$lojistId') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Turno>> listarMeusTurnos(int motoboyId) async {
    final list = await _get('/turnos?motoboyId=$motoboyId') as List<dynamic>;
    return list.map((e) => Turno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Turno> criarTurno(Turno turno) async {
    final data = await _post('/turnos', turno.toJson());
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> aceitarTurno(int turnoId, int motoboyId) async {
    final data = await _put('/turnos/$turnoId/aceitar', {'motoboyId': motoboyId});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> finalizarTurno(int turnoId) async {
    final data = await _put('/turnos/$turnoId/finalizar', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> cancelarTurno(int turnoId) async {
    final data = await _put('/turnos/$turnoId/cancelar', {});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> confirmarPagamentoLojista(int turnoId, int lojistaId) async {
    final data = await _put(
        '/turnos/$turnoId/confirmar-pagamento-lojista',
        {'lojistaId': lojistaId});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<Turno> confirmarRecebimentoMotoboy(int turnoId, int motoboyId) async {
    final data = await _put(
        '/turnos/$turnoId/confirmar-recebimento-motoboy',
        {'motoboyId': motoboyId});
    return Turno.fromJson(data as Map<String, dynamic>);
  }

  Future<List<int>> buscarTurnosAvaliados(int usuarioId) async {
    final data = await _get('/avaliacoes/feitas/$usuarioId');
    final ids = (data as Map<String, dynamic>)['turnoIds'] as List<dynamic>;
    return ids.cast<int>();
  }

  // --------------------------------------------------------
  // CARTEIRA — /api/carteira/{motoboyId}
  // --------------------------------------------------------

  Future<Carteira> buscarCarteira(int motoboyId) async {
    final data = await _get('/carteira/$motoboyId');
    return Carteira.fromJson(data as Map<String, dynamic>);
  }

  Future<void> solicitarSaque(int motoboyId, double valor) async {
    await _post('/carteira/$motoboyId/saque', {'valor': valor});
  }

  // --------------------------------------------------------
  // TRANSAÇÕES — /api/transacoes
  // --------------------------------------------------------

  Future<List<Transacao>> listarTransacoes(int motoboyId, {int limit = 20}) async {
    final list =
        await _get('/transacoes?motoboyId=$motoboyId&limit=$limit') as List<dynamic>;
    return list.map((e) => Transacao.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --------------------------------------------------------
  // DASHBOARD LOJISTA — /api/dashboard/lojista/{id}
  // --------------------------------------------------------

  Future<Map<String, dynamic>> dashboardLojista(int lojistId) async {
    final data = await _get('/dashboard/lojista/$lojistId');
    return data as Map<String, dynamic>;
  }

  // --------------------------------------------------------
  // DASHBOARD MOTOBOY — /api/dashboard/motoboy/{id}
  // --------------------------------------------------------

  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) async {
    final data = await _get('/dashboard/motoboy/$motoboyId');
    return data as Map<String, dynamic>;
  }

  // --------------------------------------------------------
  // SUGESTÕES IA — GET /api/sugestoes/turnos/{motoboyId}
  // --------------------------------------------------------

  Future<String> buscarSugestoesTurnos(int motoboyId) async {
    final data = await _get('/sugestoes/turnos/$motoboyId');
    return (data as Map<String, dynamic>)['sugestoes'] as String;
  }

  // --------------------------------------------------------
  // RELATÓRIO IA — /api/relatorio
  // --------------------------------------------------------

  Future<Map<String, dynamic>> buscarRelatorioMotoboy(int motoboyId) async {
    final data = await _get('/relatorio/motoboy/$motoboyId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buscarRelatorioLojista(int lojistaId) async {
    final data = await _get('/relatorio/lojista/$lojistaId');
    return data as Map<String, dynamic>;
  }

  // --------------------------------------------------------
  // SCORE ANALISE IA — /api/score/{motoboyId}/analise
  // --------------------------------------------------------

  Future<Map<String, dynamic>> buscarAnaliseScore(int motoboyId) async {
    final data = await _get('/score/$motoboyId/analise');
    return data as Map<String, dynamic>;
  }

  // --------------------------------------------------------
  // AGENDA — /api/agenda/{usuarioId}
  // --------------------------------------------------------

  Future<Map<String, dynamic>> buscarAgendaMensal(
      int usuarioId, int mes, int ano) async {
    final data = await _get('/agenda/$usuarioId?mes=$mes&ano=$ano');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> buscarAgendaSemanal(
      int usuarioId, String data) async {
    final d = await _get('/agenda/$usuarioId/semana?data=$data');
    return d as Map<String, dynamic>;
  }

  // --------------------------------------------------------
  // AVALIAÇÕES — /api/avaliacoes
  // --------------------------------------------------------

  Future<Map<String, dynamic>> buscarAvaliacoes(int usuarioId) async {
    final data = await _get('/avaliacoes/usuario/$usuarioId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registrarAvaliacao(
      Map<String, dynamic> body) async {
    final data = await _post('/avaliacoes', body);
    return data as Map<String, dynamic>;
  }

  Future<bool> verificarPendente(int turnoId, int usuarioId) async {
    final data =
        await _get('/avaliacoes/turno/$turnoId/pendentes/$usuarioId');
    return (data as Map<String, dynamic>)['precisaAvaliar'] as bool;
  }

  // --------------------------------------------------------
  // CARTEIRA — novos endpoints
  // --------------------------------------------------------

  Future<List<Map<String, dynamic>>> buscarGrafico(int motoboyId,
      {int meses = 6}) async {
    final list =
        await _get('/carteira/$motoboyId/grafico?meses=$meses') as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> atualizarPix(int motoboyId, String chavePix) async {
    await _put('/carteira/$motoboyId/pix', {'chavePix': chavePix});
  }

  // --------------------------------------------------------
  // TURNOS DISPONÍVEIS COM FILTROS
  // --------------------------------------------------------

  Future<List<Turno>> listarTurnosDisponiveisComFiltros({
    String? horarioInicio,
    String? horarioFim,
    int? diaSemana,
    double? raioMaxKm,
    String? dataInicio,
    String? dataFim,
    String? ordenarPor,
  }) async {
    final params = <String, String>{};
    if (horarioInicio != null) params['horarioInicio'] = horarioInicio;
    if (horarioFim != null) params['horarioFim'] = horarioFim;
    if (diaSemana != null) params['diaSemana'] = diaSemana.toString();
    if (raioMaxKm != null) params['raioMaxKm'] = raioMaxKm.toString();
    if (dataInicio != null) params['dataInicio'] = dataInicio;
    if (dataFim != null) params['dataFim'] = dataFim;
    if (ordenarPor != null) params['ordenarPor'] = ordenarPor;

    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final list =
        await _get('/turnos/disponiveis$query') as List<dynamic>;
    return list
        .map((e) => Turno.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --------------------------------------------------------
  // PERFIL PÚBLICO — /api/avaliacoes/usuario/{id}
  // --------------------------------------------------------

  Future<Map<String, dynamic>> buscarPerfilPublico(int usuarioId) async {
    final data = await _get('/avaliacoes/usuario/$usuarioId');
    return data as Map<String, dynamic>;
  }
}
