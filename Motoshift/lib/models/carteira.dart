import 'transacao.dart';

// Mapeado para CarteiraResponse no Spring Boot
class Carteira {
  final int? id;
  final int motoboyId;
  final double saldoAtual;
  final double ganhosMensais;
  final DateTime? atualizadoEm;
  final List<Transacao> transacoes;

  const Carteira({
    this.id,
    required this.motoboyId,
    required this.saldoAtual,
    required this.ganhosMensais,
    this.atualizadoEm,
    this.transacoes = const [],
  });

  double get mediaPorTurno {
    final turnos = transacoes.where((t) => t.tipo == TipoTransacao.turno).toList();
    if (turnos.isEmpty) return 0;
    return turnos.fold(0.0, (sum, t) => sum + t.valor) / turnos.length;
  }

  factory Carteira.fromJson(Map<String, dynamic> json) {
    final rawTransacoes = json['transacoes'] as List<dynamic>? ?? [];
    return Carteira(
      id: json['id'] as int?,
      motoboyId: json['motoboyId'] as int,
      saldoAtual: (json['saldoAtual'] as num).toDouble(),
      ganhosMensais: (json['ganhosMensais'] as num).toDouble(),
      atualizadoEm: json['atualizadoEm'] != null
          ? DateTime.parse(json['atualizadoEm'] as String)
          : null,
      transacoes: rawTransacoes
          .map((e) => Transacao.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'motoboyId': motoboyId,
      'saldoAtual': saldoAtual,
      'ganhosMensais': ganhosMensais,
      if (atualizadoEm != null) 'atualizadoEm': atualizadoEm!.toIso8601String(),
    };
  }
}
