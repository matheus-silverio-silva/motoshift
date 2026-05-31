import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';
import 'api_service.dart';

// Provider de autenticação — envolve ApiService e SharedPreferences
class AuthService extends ChangeNotifier {
  final ApiService _api;

  Usuario? _usuario;
  bool _carregando = false;
  String? _erro;

  AuthService(this._api);

  Usuario? get usuario => _usuario;
  bool get carregando => _carregando;
  String? get erro => _erro;
  bool get autenticado => _usuario != null;

  Future<void> inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getInt('user_id');
    if (token != null && userId != null) {
      _api.setAuthToken(token);
      try {
        _usuario = await _api.buscarUsuario(userId);
        notifyListeners();
      } catch (_) {
        await _logout();
      }
    }
  }

  Future<bool> login(String email, String senha, TipoUsuario tipo) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final resp = await _api.login(email: email, senha: senha, tipo: tipo);
      final token = resp['token'] as String;
      final userData = resp['usuario'] as Map<String, dynamic>;
      _usuario = Usuario.fromJson(userData);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setInt('user_id', _usuario!.id!);
      return true;
    } on ApiException catch (e) {
      _erro = switch (e.statusCode) {
        0   => 'Sem conexao com o servidor',
        500 => 'Erro interno, tente novamente',
        _   => e.message, // 401 inclui tentativas restantes; 429 inclui tempo de bloqueio
      };
      return false;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> registrar(Usuario usuario, String senha) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final resp = await _api.registrar(usuario, senha);
      final token = resp['token'] as String;
      final userData = resp['usuario'] as Map<String, dynamic>;
      _usuario = Usuario.fromJson(userData);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setInt('user_id', _usuario!.id!);
      return true;
    } on ApiException catch (e) {
      _erro = e.message;
      return false;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _logout();
    notifyListeners();
  }

  void atualizarUsuarioLocal(Usuario novo) {
    _usuario = novo;
    notifyListeners();
  }

  Future<void> _logout() async {
    _usuario = null;
    _api.clearAuthToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
  }
}
