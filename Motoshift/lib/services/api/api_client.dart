import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
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
    if (_apiUrl.isNotEmpty) return '$_apiUrl/api';
    // 10.0.2.2 é como o emulador Android enxerga o localhost da máquina.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    return 'http://localhost:8080/api';
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

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return _enviar(() =>
        http.post(_uri(path), headers: _headers, body: jsonEncode(body)));
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    return _enviar(() =>
        http.put(_uri(path), headers: _headers, body: jsonEncode(body)));
  }

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
