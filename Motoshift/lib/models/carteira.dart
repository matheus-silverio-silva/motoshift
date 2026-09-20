import 'transacao.dart';

// Mapeado para CarteiraResponse no Spring Boot
class Carteira {
  final int? id;
  final int motoboyId;

  /// O que pode ser gasto ou sacado agora.
  final double saldoDisponivel;

  /// Reservado para turnos publicados e ainda não encerrados.
  ///
  /// Para o lojista, é o dinheiro que ele já comprometeu ao publicar; para o
  /// entregador, é sempre zero — ele nunca reserva nada.
  final double saldoBloqueado;

  final double ganhosMensais;
  final DateTime? atualizadoEm;
  final List<Transacao> transacoes;

  const Carteira({
    this.id,
    required this.motoboyId,
    required this.saldoDisponivel,
    this.saldoBloqueado = 0,
    required this.ganhosMensais,
    this.atualizadoEm,
    this.transacoes = const [],
  });

  /// Disponível + bloqueado: o que o usuário tem na plataforma.
  double get saldoTotal => saldoDisponivel + saldoBloqueado;

  /// @deprecated Nome antigo de [saldoDisponivel]. Mantido porque várias telas
  /// ainda o leem; some quando todas migrarem.
  double get saldoAtual => saldoDisponivel;

  /// Média do que o entregador recebeu por turno.
  ///
  /// Conta `turno` (o tipo legado) e `pagamento_recebido` (o que a liquidação
  /// automática emite) — olhar só o legado faria a média congelar no histórico
  /// antigo. E só o que já foi liquidado: transação pendente é dinheiro que
  /// ainda não chegou.
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
      saldoDisponivel:
          ((json['saldoDisponivel'] ?? json['saldoAtual']) as num?)?.toDouble() ??
              0,
      saldoBloqueado: (json['saldoBloqueado'] as num?)?.toDouble() ?? 0,
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
      'saldoDisponivel': saldoDisponivel,
      'saldoBloqueado': saldoBloqueado,
      'saldoAtual': saldoDisponivel,
      'ganhosMensais': ganhosMensais,
      if (atualizadoEm != null) 'atualizadoEm': atualizadoEm!.toIso8601String(),
    };
  }
}
