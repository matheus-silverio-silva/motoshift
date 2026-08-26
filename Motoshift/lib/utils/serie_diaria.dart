import '../models/turno.dart';

/// Um dia da série de 7 dias exibida no gráfico do dashboard.
class PontoDiario {
  const PontoDiario({
    required this.dia,
    required this.label,
    required this.valor,
  });

  final DateTime dia;

  /// Abreviação do dia da semana ("Seg", "Ter", ...).
  final String label;
  final double valor;
}

const _rotulosSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// Série dos últimos 7 dias (hoje inclusive) somando o valor dos turnos
/// finalizados em cada dia.
///
/// O backend não expõe série diária: `/api/dashboard/{papel}/{id}` devolve
/// apenas acumulados (`totalGasto`, `ganhosMensais`). A série é derivada aqui
/// da lista de turnos que a tela já carregou, usando a mesma definição do
/// backend — turno com status `finalizado`, somando `valorEstimado` uma vez
/// por turno (ver `DashboardController.totalGasto`). O dia do turno é o de
/// `dataFim`, que é quando o valor de fato entra.
List<PontoDiario> serieUltimos7Dias(Iterable<Turno> turnos, {DateTime? hoje}) {
  final base = hoje ?? DateTime.now();
  final fim = DateTime(base.year, base.month, base.day);
  final inicio = fim.subtract(const Duration(days: 6));

  final totais = <DateTime, double>{};
  for (final t in turnos) {
    if (t.status != StatusTurno.finalizado) continue;
    final dia = DateTime(t.dataFim.year, t.dataFim.month, t.dataFim.day);
    if (dia.isBefore(inicio) || dia.isAfter(fim)) continue;
    totais[dia] = (totais[dia] ?? 0) + t.valorEstimado;
  }

  return List.generate(7, (i) {
    final dia = inicio.add(Duration(days: i));
    return PontoDiario(
      dia: dia,
      // DateTime.weekday: 1 = segunda ... 7 = domingo.
      label: _rotulosSemana[dia.weekday - 1],
      valor: totais[dia] ?? 0,
    );
  });
}
