import '../../models/usuario.dart';
import 'api_client.dart';

/// Sessão e perfil: `/api/auth` e `/api/usuarios`.
class AuthApi {
  final ApiClient _client;

  AuthApi(this._client);

  /// E-mail e senha, e mais nada: o backend descobre o perfil pela conta. O
  /// `tipo` que o app mandava aqui era ignorado do outro lado (SCRUM-49).
  Future<Map<String, dynamic>> login({
    required String email,
    required String senha,
  }) async {
    final data = await _client.post('/auth/login', {
      'email': email,
      'senha': senha,
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

  // ── Senha (SCRUM-32) ──────────────────────────────────────────────────────

  /// Troca a senha de quem está logado. A senha atual errada volta como
  /// `ApiException(400)` — e não 401, que o [ApiClient] trataria como sessão
  /// expirada e derrubaria o login de quem só errou um campo.
  Future<void> trocarSenha({
    required String senhaAtual,
    required String senhaNova,
  }) async {
    await _client.post('/auth/trocar-senha', {
      'senhaAtual': senhaAtual,
      'senhaNova': senhaNova,
    });
  }

  /// Pede o código de 6 dígitos. O backend responde 202 exista ou não a
  /// conta: daqui não dá para saber se o e-mail está cadastrado, de propósito.
  Future<void> esqueciSenha(String email) async {
    await _client.post('/auth/esqueci-senha', {'email': email});
  }

  /// Redefine a senha com o código recebido por e-mail.
  Future<void> redefinirSenha({
    required String email,
    required String codigo,
    required String senhaNova,
  }) async {
    await _client.post('/auth/redefinir-senha', {
      'email': email,
      'codigo': codigo,
      'senhaNova': senhaNova,
    });
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
