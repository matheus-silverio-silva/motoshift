import '../../models/turno.dart';

/// As regras do histórico de turnos, sem Flutter no meio.
///
/// Isto morava dentro do `State` da tela, misturado com os dois layouts. Além
/// de inchar o arquivo, deixava as regras exercitáveis só por golden — e um
/// golden que muda de cor não diz qual predicado quebrou. Aqui elas são Dart
/// puro: dá para testar "o expirado não conta como cancelado" sem montar
/// widget nenhum.
///
/// Um objeto de leitura, criado a cada build a partir da lista carregada.
class HistoricoResumo {
  const HistoricoResumo({
    required this.turnos,
    required this.avaliados,
  });

  /// Só turnos encerrados — quem carrega já filtra por `!status.ativo`.
  final List<Turno> turnos;

  /// Ids de turnos que este usuário já avaliou.
  final Set<int> avaliados;

  // ── Predicados ────────────────────────────────────────────────────────────

  bool precisaAvaliar(Turno t) =>
      t.status == StatusTurno.finalizado && !avaliados.contains(t.id);

  bool aguardandoPagamento(Turno t) =>
      t.status == StatusTurno.finalizado &&
      t.pagamentoStatus == PagamentoStatus.pendente;

  /// Lojista precisa confirmar que enviou o pagamento.
  bool lojistaPrecisaConfirmar(Turno t) =>
      aguardandoPagamento(t) && !t.lojistaJaConfirmou;

  /// Motoboy precisa confirmar que recebeu o pagamento.
  bool motoboyPrecisaConfirmar(Turno t) =>
      aguardandoPagamento(t) && !t.motoboyJaConfirmou;

  bool _pago(Turno t) =>
      t.status == StatusTurno.finalizado &&
      t.pagamentoStatus == PagamentoStatus.pago;

  /// Encerrou sem entrega e sem dinheiro trocando de mão. Cancelado e expirado
  /// recebem o mesmo tratamento visual, com o rótulo dizendo qual dos dois foi.
  bool semEntrega(Turno t) =>
      t.status == StatusTurno.cancelado || t.status == StatusTurno.expirado;

  // ── Filtro ────────────────────────────────────────────────────────────────

  List<Turno> filtrar(String filtro) {
    switch (filtro) {
      case 'avaliar':
        return turnos.where(precisaAvaliar).toList();
      case 'pagamento':
        return turnos.where(aguardandoPagamento).toList();
      case 'concluidos':
        return turnos.where(_pago).toList();
      case 'cancelados':
        return turnos
            .where((t) => t.status == StatusTurno.cancelado)
            .toList();
      case 'expirados':
        return turnos.where((t) => t.status == StatusTurno.expirado).toList();
      default:
        return turnos;
    }
  }

  // ── Contadores ────────────────────────────────────────────────────────────

  int get total => turnos.length;
  int get qtdAvaliar => turnos.where(precisaAvaliar).length;
  int get qtdPagamento => turnos.where(aguardandoPagamento).length;
  int get qtdConcluidos => turnos.where(_pago).length;
  int get qtdCancelados =>
      turnos.where((t) => t.status == StatusTurno.cancelado).length;
  int get qtdExpirados =>
      turnos.where((t) => t.status == StatusTurno.expirado).length;
  int get qtdFinalizados =>
      turnos.where((t) => t.status == StatusTurno.finalizado).length;

  double get valorPendente => turnos
      .where(aguardandoPagamento)
      .fold(0.0, (acc, t) => acc + t.valorEstimado);

  double get totalGanho =>
      turnos.where(_pago).fold(0.0, (acc, t) => acc + t.valorEstimado);

  double get horasRodadas => turnos
      .where((t) => t.status == StatusTurno.finalizado)
      .fold(0.0, (acc, t) => acc + t.duracao.inMinutes / 60);

  /// Percentual de turnos que chegaram ao fim. O denominador é tudo que
  /// encerrou, inclusive expirado: turno que ninguém pegou é uma falha em
  /// preencher, e some da conta se o denominador for só finalizado+cancelado.
  int get percentualConclusao =>
      total == 0 ? 0 : (qtdFinalizados / total * 100).round();

  double get mediaPorTurno =>
      qtdFinalizados == 0 ? 0.0 : totalGanho / qtdFinalizados;

  double get mediaHoras =>
      qtdFinalizados == 0 ? 0.0 : horasRodadas / qtdFinalizados;

  /// Data do turno mais antigo da lista. A lista chega ordenada do mais
  /// recente para o mais antigo.
  DateTime? get maisAntigo => turnos.isEmpty ? null : turnos.last.dataInicio;
}
