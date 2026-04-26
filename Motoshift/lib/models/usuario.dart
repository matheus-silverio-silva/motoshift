// Mapeado para a entidade `Usuario` no Spring Boot / MySQL
// Tabela: usuarios
class Usuario {
  final int? id;
  final String nome;
  final String email;
  final String telefone;
  final TipoUsuario tipo; // 'LOJISTA' | 'MOTOBOY'
  final String? documentoFederal; // CNPJ (lojista) ou CNH (motoboy)
  final String? fotoPerfil;
  final double score;
  final DateTime? criadoEm;

  const Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.tipo,
    this.documentoFederal,
    this.fotoPerfil,
    this.score = 5.0,
    this.criadoEm,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as int?,
      nome: json['nome'] as String,
      email: json['email'] as String,
      telefone: json['telefone'] as String,
      tipo: TipoUsuario.values.byName((json['tipo'] as String).toLowerCase()),
      documentoFederal: json['documentoFederal'] as String?,
      fotoPerfil: json['fotoPerfil'] as String?,
      score: (json['score'] as num?)?.toDouble() ?? 5.0,
      criadoEm: json['criadoEm'] != null
          ? DateTime.parse(json['criadoEm'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nome': nome,
      'email': email,
      'telefone': telefone,
      'tipo': tipo.name,
      if (documentoFederal != null) 'documentoFederal': documentoFederal,
      if (fotoPerfil != null) 'fotoPerfil': fotoPerfil,
    };
  }

  Usuario copyWith({
    int? id,
    String? nome,
    String? email,
    String? telefone,
    TipoUsuario? tipo,
    String? documentoFederal,
    String? fotoPerfil,
    double? score,
    DateTime? criadoEm,
  }) {
    return Usuario(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      email: email ?? this.email,
      telefone: telefone ?? this.telefone,
      tipo: tipo ?? this.tipo,
      documentoFederal: documentoFederal ?? this.documentoFederal,
      fotoPerfil: fotoPerfil ?? this.fotoPerfil,
      score: score ?? this.score,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }
}

enum TipoUsuario { lojista, motoboy }
