import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';
import 'api_service.dart';
import 'servidor_service.dart';

// Provider de autenticação — envolve ApiService e SharedPreferences
class AuthService extends ChangeNotifier {
  final ApiService _api;

  /// Quem sabe se o backend já acordou (SCRUM-48). Mora aqui porque é a sessão
  /// que depende dele: restaurar o token salvo e entrar só fazem sentido com o
  /// servidor respondendo. A tela de login e as de carregamento o escutam para
  /// mostrar "Acordando o servidor…".
  final ServidorService servidor;

  Usuario? _usuario;
  bool _carregando = false;
  String? _erro;
  bool _inicializado = false;
  Future<void>? _inicializando;

  AuthService(this._api, {ServidorService? servidor})
      : servidor = servidor ?? ServidorService(_api) {
    // Token expirado nao e erro de tela: derruba a sessao e o AuthGuard leva
    // de volta ao login.
    _api.onSessaoExpirada = _sessaoExpirou;
  }

  Future<void> _sessaoExpirou() async {
    if (_usuario == null) return;
    await _logout();
    notifyListeners();
  }

  Usuario? get usuario => _usuario;
  bool get carregando => _carregando;
  String? get erro => _erro;
  bool get autenticado => _usuario != null;

  /// Indica se a restauração de sessão (leitura do token salvo) já rodou.
  /// Usado pelo AuthGuard para saber se pode decidir sobre redirecionamento.
  bool get inicializado => _inicializado;

  /// Restaura a sessão salva no aparelho.
  ///
  /// Com sessão salva, espera o servidor acordar antes de perguntar quem é o
  /// usuário. Se ele não responder dentro do limite, isto termina SEM
  /// inicializar ([inicializado] continua `false`) e sem mexer na sessão: a
  /// tela mostra o erro, e o "Tentar novamente" chama isto de novo.
  ///
  /// A Splash e o AuthGuard podem chamar ao mesmo tempo; as duas chamadas
  /// dividem a mesma restauração.
  Future<void> inicializar() => _inicializando ??=
      _inicializar().whenComplete(() => _inicializando = null);

  Future<void> _inicializar() async {
    if (_inicializado) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getInt('user_id');
    if (token != null && userId != null) {
      if (!await servidor.aguardar()) return;
      _api.setAuthToken(token);
      try {
        _usuario = await _api.auth.buscarUsuario(userId);
      } on ApiException catch (e) {
        // Só o servidor dizendo "esta sessão não vale" apaga a sessão salva.
        // Queda de rede ou erro interno não é resposta sobre o token: apagar
        // aqui obrigava a digitar a senha de novo por causa de um soluço.
        if (e.statusCode == 0 || e.statusCode >= 500) {
          _api.clearAuthToken();
        } else {
          await _logout();
        }
      } catch (_) {
        await _logout();
      }
    }
    _inicializado = true;
    notifyListeners();
  }

  /// Entra com e-mail e senha. O perfil não é pergunta: vem da conta, na
  /// resposta do backend.
  Future<bool> login(String email, String senha) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final resp = await _api.auth.login(email: email, senha: senha);
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
      final resp = await _api.auth.registrar(usuario, senha);
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

  @override
  void dispose() {
    servidor.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    _usuario = null;
    _api.clearAuthToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
  }
}
