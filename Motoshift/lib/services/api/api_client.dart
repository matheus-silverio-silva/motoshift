import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;
import 'package:http/http.dart' as http;

/// Erro vindo da API, já traduzido para algo que a tela pode mostrar.
///
/// `statusCode == 0` significa que a requisição nem chegou ao servidor.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// O transporte HTTP do app, e só ele: URL base, cabeçalhos, timeout,
/// tratamento de erro e token de sessão.
///
/// Antes isto morava dentro do `ApiService`, junto com os 45 endpoints — 459
/// linhas em que mexer no cabeçalho de uma chamada obrigava a abrir o arquivo
/// que também descrevia carteira, avaliação e IA. Aqui a regra de transporte é
/// escrita uma vez e as APIs de domínio a reutilizam.
class ApiClient {
  /// Injetada no build de produção via `--dart-define=API_URL=https://...`.
  static const String _apiUrl =
      String.fromEnvironment('API_URL', defaultValue: '');

  /// Sem timeout explícito, uma rede ruim deixava a tela girando para sempre.
  static const Duration _timeout = Duration(seconds: 20);

  static String get baseUrl {
    if (_apiUrl.isNotEmpty) return baseDe(_apiUrl);
    // 10.0.2.2 é como o emulador Android enxerga o localhost da máquina.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    return 'http://localhost:8080/api';
  }

  /// A base das chamadas a partir do `API_URL` do build: a URL do backend
  /// mais `/api`.
  ///
  /// Tolera a barra no fim e o `/api` escrito junto. O `API_URL` é "sem /api",
  /// mas `https://motoshift.onrender.com/api` é o que se copia do navegador —
  /// e virava `/api/api`, com todas as chamadas em 404 num build que só se
  /// descobre quebrado depois de publicado.
  @visibleForTesting
  static String baseDe(String apiUrl) {
    var url = apiUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.toLowerCase().endsWith('/api')) {
      url = url.substring(0, url.length - '/api'.length);
    }
    return '$url/api';
  }

  String? _authToken;

  /// Avisado quando o backend recusa o token de uma sessão ativa.
  ///
  /// Enquanto o token era um UUID guardado em memória no servidor, 401 depois
  /// do login só acontecia se o backend reiniciasse. Com JWT de 7 dias a sessão
  /// expira sozinha, e "erro da tela" virou "sua sessão acabou": o AuthService
  /// liga isto ao logout para o app voltar ao login em vez de mostrar erro
  /// genérico em toda tela.
  void Function()? onSessaoExpirada;

  void setAuthToken(String token) => _authToken = token;
  void clearAuthToken() => _authToken = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  Future<dynamic> get(String path) async {
    return _enviar(() => http.get(_uri(path), headers: _headers));
  }

  /// GET que também devolve o total do header `X-Total-Count`.
  ///
  /// As listagens paginadas do backend respondem um array JSON e mandam o
  /// total num header — formato escolhido para que o app antigo, que não
  /// pagina, continue lendo a mesma resposta. Sem o total, a rolagem infinita
  /// não sabe quando parar e pediria páginas vazias para sempre.
  Future<({dynamic dados, int total})> getPaginado(String path) async {
    final http.Response response;
    try {
      response = await http.get(_uri(path), headers: _headers).timeout(_timeout);
    } catch (_) {
      throw const ApiException(0, 'Sem conexao com o servidor');
    }
    final dados = _tratar(response);
    final total = int.tryParse(response.headers['x-total-count'] ?? '') ??
        (dados is List ? dados.length : 0);
    return (dados: dados, total: total);
  }

  /// GET de um corpo que não é JSON — hoje, só o CSV do extrato.
  Future<String> getTexto(String path) async {
    final http.Response response;
    try {
      response = await http.get(_uri(path), headers: _headers).timeout(_timeout);
    } catch (_) {
      throw const ApiException(0, 'Sem conexao com o servidor');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return utf8.decode(response.bodyBytes);
    }
    _tratar(response); // lança com a mensagem do backend
    return '';
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return _enviar(() =>
        http.post(_uri(path), headers: _headers, body: jsonEncode(body)));
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    return _enviar(() =>
        http.put(_uri(path), headers: _headers, body: jsonEncode(body)));
  }

  Future<dynamic> delete(String path) async {
    return _enviar(() => http.delete(_uri(path), headers: _headers));
  }

  /// O servidor está respondendo? Pergunta ao `/api/status` (SCRUM-48).
  ///
  /// Fora do [_enviar] de propósito: não manda o token (a rota é pública),
  /// não lança, e uma resposta 401 aqui nunca derruba a sessão.
  Future<bool> servidorResponde() async {
    try {
      final resposta = await http
          .get(_uri('/status'), headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
      return respostaDoBackend(
          resposta.statusCode, resposta.headers['content-type']);
    } catch (_) {
      return false;
    }
  }

  /// Foi o backend quem respondeu, e não o proxy da hospedagem?
  ///
  /// Enquanto o servidor acorda, quem atende é o proxy: 502/503 ou uma página
  /// HTML de espera. O backend sempre responde JSON — inclusive nos erros.
  /// Por isso um 401 ou 404 em JSON também conta como "no ar": é um backend
  /// acordado, só que de uma versão sem esta rota.
  @visibleForTesting
  static bool respostaDoBackend(int statusCode, String? contentType) =>
      statusCode < 500 &&
      (contentType ?? '').toLowerCase().contains('application/json');

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> _enviar(Future<http.Response> Function() requisicao) async {
    final http.Response response;
    try {
      response = await requisicao().timeout(_timeout);
    } catch (_) {
      throw const ApiException(0, 'Sem conexao com o servidor');
    }
    return _tratar(response);
  }

  dynamic _tratar(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode >= 500) {
      throw ApiException(response.statusCode, 'Erro interno, tente novamente');
    }
    // O 401 do próprio login não entra aqui: naquele momento não há token.
    if (response.statusCode == 401 && _authToken != null) {
      onSessaoExpirada?.call();
    }

    final body = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : <String, dynamic>{};

    // O backend responde {codigo, mensagem, campo} em todo erro tratado
    // (ApiExceptionHandler e RespostaDeErro escrevem o mesmo formato).
    // "message"/"error" continuam no fallback para o que escapa do handler,
    // como o 404 do Spring numa rota inexistente.
    final mensagem = body['mensagem'] ??
        body['message'] ??
        body['error'] ??
        'Erro desconhecido';
    throw ApiException(response.statusCode, mensagem.toString());
  }
}
