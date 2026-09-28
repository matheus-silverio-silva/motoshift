/// Um entregador da lista "Meus entregadores favoritos" do lojista (V18).
///
/// Só o que o perfil público já mostra — nome, nota e reputação. Contato e
/// documento não saem do backend para outra conta.
class EntregadorFavorito {
  const EntregadorFavorito({
    required this.motoboyId,
    required this.nome,
    this.mediaAvaliacao,
    this.score,
    this.favoritadoEm,
  });

  final int motoboyId;
  final String nome;
  final double? mediaAvaliacao;

  /// Nulo para o entregador ainda sem histórico — "Novo na plataforma".
  final double? score;
  final DateTime? favoritadoEm;

  factory EntregadorFavorito.fromJson(Map<String, dynamic> json) =>
      EntregadorFavorito(
        motoboyId: (json['motoboyId'] as num).toInt(),
        nome: json['nome'] as String? ?? 'Entregador',
        mediaAvaliacao: (json['mediaAvaliacao'] as num?)?.toDouble(),
        score: (json['score'] as num?)?.toDouble(),
        favoritadoEm: json['favoritadoEm'] == null
            ? null
            : DateTime.tryParse(json['favoritadoEm'] as String),
      );
}
