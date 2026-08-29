import '../../models/usuario.dart';
import 'api_client.dart';

/// Sessão e perfil: `/api/auth` e `/api/usuarios`.
class AuthApi {
  final ApiClient _client;

  AuthApi(this._client);

  Future<Map<String, dynamic>> login({
    required String email,
    required String senha,
    required TipoUsuario tipo,
  }) async {
    final data = await _client.post('/auth/login', {
      'email': email,
      'senha': senha,
      'tipo': tipo.name.toUpperCase(),
    });
    // Guarda o token já aqui: sem isto, a primeira chamada depois do login
    // sairia sem Authorization e voltaria 401.
    _client.setAuthToken(data['token'] as String);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registrar(Usuario usuario, String senha) async {
    final body = usuario.toJson()..['senha'] = senha;
    final data = await _client.post('/auth/registro', body);
    _client.setAuthToken(data['token'] as String);
    return data as Map<String, dynamic>;
  }

  Future<Usuario> buscarUsuario(int id) async {
    final data = await _client.get('/usuarios/$id');
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Usuario> atualizarUsuario(Usuario usuario) async {
    final data = await _client.put('/usuarios/${usuario.id}', usuario.toJson());
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Usuario> atualizarPerfil(int id, Map<String, dynamic> campos) async {
    final data = await _client.put('/usuarios/$id', campos);
    return Usuario.fromJson(data as Map<String, dynamic>);
  }
}
