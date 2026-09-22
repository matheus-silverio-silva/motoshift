/// Os filtros da lista de notas fiscais, como a tela os guarda e a API os
/// recebe.
///
/// Mesmo desenho do [ExtratoFiltro]: um objeto imutável que sabe virar query
/// string. O período é o da COMPETÊNCIA — a data do serviço —, não o da
/// emissão: é por competência que se procura uma nota.
class NotaFiscalFiltro {
  const NotaFiscalFiltro({
    this.papel,
    this.competenciaDe,
    this.competenciaAte,
    this.status,
    this.contraparteId,
    this.turnoId,
  });

  /// `prestador` (notas em que eu prestei) ou `tomador` (serviços que tomei).
  final String? papel;
  final DateTime? competenciaDe;
  final DateTime? competenciaAte;

  /// `emitida` ou `cancelada`.
  final String? status;
  final int? contraparteId;
  final int? turnoId;

  bool get vazio =>
      papel == null &&
      competenciaDe == null &&
      competenciaAte == null &&
      status == null &&
      contraparteId == null &&
      turnoId == null;

  NotaFiscalFiltro copyWith({
    String? papel,
    DateTime? competenciaDe,
    DateTime? competenciaAte,
    String? status,
    int? contraparteId,
    int? turnoId,
    bool limparPapel = false,
    bool limparPeriodo = false,
    bool limparStatus = false,
    bool limparContraparte = false,
  }) {
    return NotaFiscalFiltro(
      papel: limparPapel ? null : (papel ?? this.papel),
      competenciaDe: limparPeriodo ? null : (competenciaDe ?? this.competenciaDe),
      competenciaAte: limparPeriodo ? null : (competenciaAte ?? this.competenciaAte),
      status: limparStatus ? null : (status ?? this.status),
      contraparteId: limparContraparte ? null : (contraparteId ?? this.contraparteId),
      turnoId: turnoId ?? this.turnoId,
    );
  }

  /// Só o que está preenchido entra na URL: parâmetro vazio é parâmetro a
  /// mais para o backend validar.
  String toQuery() {
    String dia(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final partes = <String>[
      if (papel != null) 'papel=$papel',
      if (competenciaDe != null) 'competenciaDe=${dia(competenciaDe!)}',
      if (competenciaAte != null) 'competenciaAte=${dia(competenciaAte!)}',
      if (status != null) 'status=$status',
      if (contraparteId != null) 'contraparteId=$contraparteId',
      if (turnoId != null) 'turnoId=$turnoId',
    ];
    return partes.join('&');
  }
}
