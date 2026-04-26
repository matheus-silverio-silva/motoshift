import '../entities/usuario_entity.dart';

// ============================================================
// DOMAIN LAYER — Contrato de autenticação (RF01).
// ============================================================

abstract interface class IAuthRepository {
  Future<AuthResultEntity> login({
    required String email,
    required String senha,
    required TipoUsuarioEntity tipo,
  });

  Future<AuthResultEntity> registrar({
    required UsuarioEntity usuario,
    required String senha,
  });

  Future<void> logout();

  Future<UsuarioEntity?> restaurarSessao();
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;

  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException($statusCode): $message';
}
