/// Um selo de reputação, calculado pelo backend a partir do histórico (sem
/// tabela): o título que aparece no chip e o critério que o tocar mostra.
class Selo {
  const Selo({required this.codigo, required this.titulo, required this.criterio});

  final String codigo;
  final String titulo;
  final String criterio;

  factory Selo.fromJson(Map<String, dynamic> json) => Selo(
        codigo: json['codigo'] as String? ?? '',
        titulo: json['titulo'] as String? ?? '',
        criterio: json['criterio'] as String? ?? '',
      );

  /// Lê a lista de um JSON que pode não trazê-la (resposta antiga): vazia.
  static List<Selo> listaDe(Object? json) => json is List
      ? json.whereType<Map<String, dynamic>>().map(Selo.fromJson).toList()
      : const [];
}
