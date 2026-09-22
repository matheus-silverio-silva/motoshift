import 'transacao.dart';

/// Os filtros do extrato, do jeito que a tela os manipula e a API os recebe.
///
/// O filtro deixou de ser coisa do cliente: antes o app baixava o extrato
/// inteiro e escondia as linhas que não interessavam, o que impedia paginar e
/// não escala. Esta classe só carrega a escolha do usuário até a query string.
class ExtratoFiltro {
  final DateTime? dataInicio;
  final DateTime? dataFim;
  final Set<TipoTransacao> tipos;
  final NaturezaTransacao? natureza;
  final int? turnoId;
  final int? contraparteId;
  final double? valorMin;
  final double? valorMax;
  final String? busca;

  /// Qual atalho de período está selecionado, para a tela marcar o botão.
  /// `null` quando o usuário escolheu datas à mão.
  final AtalhoDePeriodo? atalho;

  const ExtratoFiltro({
    this.dataInicio,
    this.dataFim,
    this.tipos = const {},
    this.natureza,
    this.turnoId,
    this.contraparteId,
    this.valorMin,
    this.valorMax,
    this.busca,
    this.atalho,
  });

  /// Nenhum filtro ativo — a tela usa isto para decidir se mostra o "limpar".
  bool get vazio =>
      dataInicio == null &&
      dataFim == null &&
      tipos.isEmpty &&
      natureza == null &&
      turnoId == null &&
      contraparteId == null &&
      valorMin == null &&
      valorMax == null &&
      (busca == null || busca!.isEmpty);

  /// Quantos critérios estão ativos, para o badge do botão de filtros.
  int get quantidadeAtiva => [
        dataInicio != null || dataFim != null,
        tipos.isNotEmpty,
        natureza != null,
        turnoId != null,
        contraparteId != null,
        valorMin != null || valorMax != null,
        busca != null && busca!.isNotEmpty,
      ].where((ativo) => ativo).length;

  ExtratoFiltro copyWith({
    DateTime? dataInicio,
    DateTime? dataFim,
    Set<TipoTransacao>? tipos,
    NaturezaTransacao? natureza,
    int? turnoId,
    int? contraparteId,
    double? valorMin,
    double? valorMax,
    String? busca,
    AtalhoDePeriodo? atalho,
    bool limparPeriodo = false,
    bool limparNatureza = false,
    bool limparTurno = false,
    bool limparValores = false,
  }) {
    return ExtratoFiltro(
      dataInicio: limparPeriodo ? null : (dataInicio ?? this.dataInicio),
      dataFim: limparPeriodo ? null : (dataFim ?? this.dataFim),
      tipos: tipos ?? this.tipos,
      natureza: limparNatureza ? null : (natureza ?? this.natureza),
      turnoId: limparTurno ? null : (turnoId ?? this.turnoId),
      contraparteId: limparTurno ? null : (contraparteId ?? this.contraparteId),
      valorMin: limparValores ? null : (valorMin ?? this.valorMin),
      valorMax: limparValores ? null : (valorMax ?? this.valorMax),
      busca: busca ?? this.busca,
      atalho: limparPeriodo ? null : (atalho ?? this.atalho),
    );
  }

  /// A query string que a API entende. Filtro ausente não vira parâmetro —
  /// `null` significa "não filtre por isso", nunca "filtre por nada".
  Map<String, String> get parametros {
    final p = <String, String>{};
    if (dataInicio != null) p['dataInicio'] = _data(dataInicio!);
    if (dataFim != null) p['dataFim'] = _data(dataFim!);
    if (tipos.isNotEmpty) {
      p['tipos'] = tipos.map((t) => t.valorApi).join(',');
    }
    if (natureza != null) p['natureza'] = natureza!.name;
    if (turnoId != null) p['turnoId'] = '$turnoId';
    if (contraparteId != null) p['contraparteId'] = '$contraparteId';
    if (valorMin != null) p['valorMin'] = valorMin!.toStringAsFixed(2);
    if (valorMax != null) p['valorMax'] = valorMax!.toStringAsFixed(2);
    if (busca != null && busca!.isNotEmpty) p['busca'] = busca!;
    return p;
  }

  static String _data(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Os recortes de período que a tela oferece com um toque.
enum AtalhoDePeriodo {
  seteDias,
  trintaDias,
  mesAtual,
  mesAnterior;

  String get label {
    return switch (this) {
      AtalhoDePeriodo.seteDias => '7 dias',
      AtalhoDePeriodo.trintaDias => '30 dias',
      AtalhoDePeriodo.mesAtual => 'Mês atual',
      AtalhoDePeriodo.mesAnterior => 'Mês anterior',
    };
  }

  /// O intervalo que este atalho representa, a partir de uma data de
  /// referência. Recebe `hoje` em vez de chamar `DateTime.now()` para que o
  /// teste possa fixar o dia.
  (DateTime, DateTime) intervalo(DateTime hoje) {
    return switch (this) {
      AtalhoDePeriodo.seteDias => (hoje.subtract(const Duration(days: 6)), hoje),
      AtalhoDePeriodo.trintaDias =>
        (hoje.subtract(const Duration(days: 29)), hoje),
      AtalhoDePeriodo.mesAtual => (DateTime(hoje.year, hoje.month, 1), hoje),
      // Dia 0 do mês atual é o último dia do mês anterior — evita a conta de
      // "quantos dias tem fevereiro".
      AtalhoDePeriodo.mesAnterior => (
          DateTime(hoje.year, hoje.month - 1, 1),
          DateTime(hoje.year, hoje.month, 0),
        ),
    };
  }
}
