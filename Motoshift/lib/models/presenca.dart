/// Quando o entregador chegou e saiu de um turno — o check-in e o check-out
/// (V16), como vêm em `GET /turnos/{id}/inscritos`.
///
/// O backend só manda a presença de cada inscrito para o lojista do turno e
/// para o próprio entregador; para o colega de outra vaga as chaves nem vêm,
/// e isto fica [vazia].
class Presenca {
  const Presenca({this.chegada, this.saida, this.minutosDoInicio});

  factory Presenca.doInscrito(Map<String, dynamic> m) {
    DateTime? data(String chave) {
      final v = m[chave];
      return v is String && v.isNotEmpty ? DateTime.parse(v) : null;
    }

    return Presenca(
      chegada: data('checkinEm'),
      saida: data('checkoutEm'),
      minutosDoInicio: (m['minutosDoInicio'] as num?)?.toInt(),
    );
  }

  static const vazia = Presenca();

  final DateTime? chegada;
  final DateTime? saida;

  /// Minutos entre o início marcado e a chegada, contados pelo backend:
  /// negativo = chegou antes.
  final int? minutosDoInicio;

  bool get chegou => chegada != null;
  bool get saiu => saida != null;

  /// "3 min antes", "no horário", "12 min depois".
  String? get relativoAoInicio {
    final m = minutosDoInicio;
    if (m == null) return null;
    if (m == 0) return 'no horário';
    return '${m.abs()} min ${m < 0 ? 'antes' : 'depois'}';
  }

  /// "Chegou às 14:03 (3 min antes)".
  String? get rotuloChegada {
    if (chegada == null) return null;
    final rel = relativoAoInicio;
    return 'Chegou às ${_hora(chegada!)}${rel == null ? '' : ' ($rel)'}';
  }

  /// "saiu às 18:02".
  String? get rotuloSaida => saida == null ? null : 'saiu às ${_hora(saida!)}';

  /// As duas coisas numa linha, para o card do entregador no turno do lojista.
  String? get resumo {
    final c = rotuloChegada;
    if (c == null) return null;
    final s = rotuloSaida;
    return s == null ? c : '$c · $s';
  }

  static String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
