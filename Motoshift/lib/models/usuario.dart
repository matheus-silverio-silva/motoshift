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

  /// Reputação do entregador (0 a 5). Nula para o lojista, que não tem score,
  /// e para o entregador sem histórico — "Novo na plataforma", e não um 5,0
  /// que nenhum turno produziu. Ver `Reputacao` no backend.
  final double? score;

  /// Média das avaliações recebidas. Nula enquanto ninguém avaliou.
  final double? mediaAvaliacao;

  // Dados pessoais
  final DateTime? dataNascimento;
  final String? cidade;
  final String? estado;

  // CNH e Veículo (motoboy)
  final String? cnhNumero;
  final String? cnhCategoria;
  final DateTime? cnhValidade;
  final String? veiculoModelo;
  final String? veiculoPlaca;
  final int? veiculoAno;
  final String? veiculoCor;

  // Lojista
  final String? nomeFantasia;
  final String? enderecoComercial;

  /// Ponto da loja no mapa (V15), marcado em "Dados pessoais". É de onde a
  /// publicação de turno parte: sem ele, o pino do turno vinha do GPS de onde
  /// o lojista estivesse publicando — a casa dele —, enquanto o endereço
  /// escrito era o da loja. Nulo para o entregador e para quem não marcou.
  final double? latitude;
  final double? longitude;

  final DateTime? criadoEm;

  /// A loja já marcou o ponto no mapa?
  bool get temPontoDaLoja => latitude != null && longitude != null;

  const Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.tipo,
    this.documentoFederal,
    this.fotoPerfil,
    this.score,
    this.mediaAvaliacao,
    this.dataNascimento,
    this.cidade,
    this.estado,
    this.cnhNumero,
    this.cnhCategoria,
    this.cnhValidade,
    this.veiculoModelo,
    this.veiculoPlaca,
    this.veiculoAno,
    this.veiculoCor,
    this.nomeFantasia,
    this.enderecoComercial,
    this.latitude,
    this.longitude,
    this.criadoEm,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String key) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return DateTime.parse(v);
      return null;
    }

    return Usuario(
      id: json['id'] as int?,
      nome: json['nome'] as String,
      // Perfil de OUTRA conta chega reduzido (PerfilPublicoResponse no
      // backend): sem e-mail, telefone, documento, CNH nem endereço. Com
      // `as String` direto, `null as String` lançava TypeError e a tela do
      // turno caía no "Motoboy #id" em vez de mostrar o nome.
      email: json['email'] as String? ?? '',
      telefone: json['telefone'] as String? ?? '',
      tipo: TipoUsuario.values.byName((json['tipo'] as String).toLowerCase()),
      documentoFederal: json['documentoFederal'] as String?,
      fotoPerfil: json['fotoPerfil'] as String?,
      score: (json['score'] as num?)?.toDouble(),
      mediaAvaliacao: (json['mediaAvaliacao'] as num?)?.toDouble(),
      dataNascimento: parseDate('dataNascimento'),
      cidade: json['cidade'] as String?,
      estado: json['estado'] as String?,
      cnhNumero: json['cnhNumero'] as String?,
      cnhCategoria: json['cnhCategoria'] as String?,
      cnhValidade: parseDate('cnhValidade'),
      veiculoModelo: json['veiculoModelo'] as String?,
      veiculoPlaca: json['veiculoPlaca'] as String?,
      veiculoAno: json['veiculoAno'] as int?,
      veiculoCor: json['veiculoCor'] as String?,
      nomeFantasia: json['nomeFantasia'] as String?,
      enderecoComercial: json['enderecoComercial'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      criadoEm: parseDate('criadoEm'),
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
    double? mediaAvaliacao,
    DateTime? dataNascimento,
    String? cidade,
    String? estado,
    String? cnhNumero,
    String? cnhCategoria,
    DateTime? cnhValidade,
    String? veiculoModelo,
    String? veiculoPlaca,
    int? veiculoAno,
    String? veiculoCor,
    String? nomeFantasia,
    String? enderecoComercial,
    double? latitude,
    double? longitude,
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
      mediaAvaliacao: mediaAvaliacao ?? this.mediaAvaliacao,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      cnhNumero: cnhNumero ?? this.cnhNumero,
      cnhCategoria: cnhCategoria ?? this.cnhCategoria,
      cnhValidade: cnhValidade ?? this.cnhValidade,
      veiculoModelo: veiculoModelo ?? this.veiculoModelo,
      veiculoPlaca: veiculoPlaca ?? this.veiculoPlaca,
      veiculoAno: veiculoAno ?? this.veiculoAno,
      veiculoCor: veiculoCor ?? this.veiculoCor,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      enderecoComercial: enderecoComercial ?? this.enderecoComercial,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }
}

enum TipoUsuario { lojista, motoboy }
