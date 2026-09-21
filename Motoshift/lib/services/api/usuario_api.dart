import '../../models/perfil_publico.dart';
import 'api_client.dart';

/// Perfil de outras contas.
///
/// `GET /api/usuarios/{id}` devolve o perfil COMPLETO para o próprio dono e o
/// [PerfilPublico] reduzido para qualquer outra conta — o recorte é do
/// backend, não do app. Aqui só existe a leitura pública: o perfil do próprio
/// usuário já vem do [AuthService] no login.
class UsuarioApi {
  final ApiClient _client;

  UsuarioApi(this._client);

  Future<PerfilPublico> buscarPerfilPublico(int usuarioId) async {
    final data = await _client.get('/usuarios/$usuarioId');
    return PerfilPublico.fromJson(data as Map<String, dynamic>);
  }
}
