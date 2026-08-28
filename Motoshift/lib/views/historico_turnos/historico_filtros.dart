import 'historico_resumo.dart';

/// Uma aba da barra de filtros do histórico.
class OpcaoFiltroHistorico {
  const OpcaoFiltroHistorico(this.chave, this.rotulo, this.contagem);

  final String chave;
  final String rotulo;
  final int contagem;
}

/// As abas, na ordem, com a contagem de cada uma.
///
/// Mobile e desktop desenham a barra de formas diferentes — pílulas roláveis
/// contra uma linha fixa — mas o conjunto de abas tem que ser o mesmo. Estava
/// duplicado nos dois métodos, e foi assim que "Expirados" quase entrou só num
/// deles.
List<OpcaoFiltroHistorico> opcoesFiltroHistorico(
  HistoricoResumo resumo,
  bool isLojista,
) =>
    [
      OpcaoFiltroHistorico('todos', 'Todos', resumo.total),
      OpcaoFiltroHistorico('avaliar', 'A avaliar', resumo.qtdAvaliar),
      OpcaoFiltroHistorico('pagamento', isLojista ? 'A pagar' : 'A receber',
          resumo.qtdPagamento),
      OpcaoFiltroHistorico('concluidos', 'Concluídos', resumo.qtdConcluidos),
      OpcaoFiltroHistorico('cancelados', 'Cancelados', resumo.qtdCancelados),
      OpcaoFiltroHistorico('expirados', 'Expirados', resumo.qtdExpirados),
    ];
