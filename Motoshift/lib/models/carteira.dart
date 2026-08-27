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

  /// Média do que o entregador recebeu por turno.
  ///
  /// Conta `turno` (o tipo legado) e `pagamento_recebido` (o que a liquidação
  /// automática passa a emitir) — olhar só o legado faria a média congelar no
  /// histórico antigo. E só o que já foi liquidado: transação pendente é
  /// dinheiro que ainda não chegou.
  double get mediaPorTurno {
    final turnos = transacoes
        .where((t) =>
            (t.tipo == TipoTransacao.turno ||
                t.tipo == TipoTransacao.pagamentoRecebido) &&
            t.status.liquidado)
        .toList();
    if (turnos.isEmpty) return 0;
    return turnos.fold(0.0, (sum, t) => sum + t.valor) / turnos.length;
  }

  factory Carteira.fromJson(Map<String, dynamic> json) {
    final rawTransacoes = json['transacoes'] as List<dynamic>? ?? [];
    return Carteira(
      id: json['id'] as int?,
      // Mesma leitura defensiva do extrato: `usuarioId` é o campo real desde a
      // etapa 2 e `motoboyId` é só espelho. `null as int` lança TypeError em
      // Dart, e a carteira de um usuário novo nasce sem motoboy_id.
      motoboyId: (json['usuarioId'] ?? json['motoboyId']) as int? ?? 0,
      saldoAtual: (json['saldoDisponivel'] ?? json['saldoAtual'] as num?)
              ?.toDouble() ??
          0,
      ganhosMensais: (json['ganhosMensais'] as num?)?.toDouble() ?? 0,
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
