import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/usuario_entity.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../models/usuario.dart' show TipoUsuario;
import '../../services/api_service.dart';

// ============================================================
// DATA LAYER — Implementação de IAuthRepository (RF01).
// Delega chamadas HTTP ao ApiService e persiste o token.
// ============================================================

class AuthRepositoryImpl implements IAuthRepository {
  final ApiService _api;

  AuthRepositoryImpl(this._api);

  @override
  Future<AuthResultEntity> login({
    required String email,
    required String senha,
    required TipoUsuarioEntity tipo,
  }) async {
    try {
      final data = await _api.login(
        email: email,
        senha: senha,
        tipo: _toTipoUsuario(tipo),
      );
      final result = _parseAuthResult(data);
      await _persistirSessao(result.token, result.usuario.id);
      return result;
    } on ApiException catch (e) {
      throw AuthException(e.message, statusCode: e.statusCode);
    }
  }

  @override
  Future<AuthResultEntity> registrar({
    required UsuarioEntity usuario,
    required String senha,
  }) async {
    try {
      final body = {
        'nome': usuario.nome,
        'email': usuario.email,
        'telefone': usuario.telefone,
        'tipo': usuario.tipo.name.toUpperCase(),
        if (usuario.documentoFederal != null)
          'documentoFederal': usuario.documentoFederal,
        'senha': senha,
      };
      final data = await _api.rawPost('/auth/registro', body);
      final result = _parseAuthResult(data as Map<String, dynamic>);
      await _persistirSessao(result.token, result.usuario.id);
      return result;
    } on ApiException catch (e) {
      throw AuthException(e.message, statusCode: e.statusCode);
    }
  }

  @override
  Future<void> logout() async {
    _api.clearAuthToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
  }

  @override
  Future<UsuarioEntity?> restaurarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getInt('user_id');
    if (token == null || userId == null) return null;

    _api.setAuthToken(token);
    try {
      final usuario = await _api.buscarUsuario(userId);
      return _usuarioToEntity(usuario);
    } on ApiException {
      await logout();
      return null;
    }
  }

  // ------ helpers ------

  Future<void> _persistirSessao(String token, int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    if (userId != null) await prefs.setInt('user_id', userId);
    _api.setAuthToken(token);
  }

  AuthResultEntity _parseAuthResult(Map<String, dynamic> data) {
    final token = data['token'] as String;
    final userData = data['usuario'] as Map<String, dynamic>;
    return AuthResultEntity(token: token, usuario: _usuarioFromJson(userData));
  }

  UsuarioEntity _usuarioFromJson(Map<String, dynamic> json) {
    return UsuarioEntity(
      id: json['id'] as int?,
      nome: json['nome'] as String,
      email: json['email'] as String,
      telefone: json['telefone'] as String,
      tipo: TipoUsuarioEntity.values
          .byName((json['tipo'] as String).toLowerCase()),
      documentoFederal: json['documentoFederal'] as String?,
      fotoPerfil: json['fotoPerfil'] as String?,
      criadoEm: json['criadoEm'] != null
          ? DateTime.parse(json['criadoEm'] as String)
          : null,
    );
  }

  UsuarioEntity _usuarioToEntity(dynamic u) {
    return UsuarioEntity(
      id: u.id as int?,
      nome: u.nome as String,
      email: u.email as String,
      telefone: u.telefone as String,
      tipo: TipoUsuarioEntity.values.byName(u.tipo.name),
      documentoFederal: u.documentoFederal as String?,
      fotoPerfil: u.fotoPerfil as String?,
    );
  }

  TipoUsuario _toTipoUsuario(TipoUsuarioEntity t) =>
      t == TipoUsuarioEntity.lojista ? TipoUsuario.lojista : TipoUsuario.motoboy;
}
