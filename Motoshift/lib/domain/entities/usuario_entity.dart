// ============================================================
// DOMAIN LAYER — Entidade pura do usuário (RF01).
// Não depende de Flutter, JSON ou http.
// ============================================================

enum TipoUsuarioEntity {
  lojista,
  motoboy;

  String get label => switch (this) {
        TipoUsuarioEntity.lojista => 'Lojista',
        TipoUsuarioEntity.motoboy => 'Motoboy',
      };
}

class UsuarioEntity {
  final int? id;
  final String nome;
  final String email;
  final String telefone;
  final TipoUsuarioEntity tipo;
  final String? documentoFederal;
  final String? fotoPerfil;
  final DateTime? criadoEm;

  const UsuarioEntity({
    this.id,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.tipo,
    this.documentoFederal,
    this.fotoPerfil,
    this.criadoEm,
  });
}

class AuthResultEntity {
  final String token;
  final UsuarioEntity usuario;

  const AuthResultEntity({required this.token, required this.usuario});
}
