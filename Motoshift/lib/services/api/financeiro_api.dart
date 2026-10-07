import '../../models/dre.dart';
import '../../models/lancamento_gerencial.dart';
import 'api_client.dart';

/// Resultado financeiro: a DRE e os lançamentos que o usuário informa —
/// `/api/financeiro` (RF13).
///
/// Nenhuma chamada leva id de usuário nem papel: o backend lê os dois do
/// token. Não há "DRE de outra pessoa" a pedir.
class FinanceiroApi {
  final ApiClient _client;

  FinanceiroApi(this._client);

  // ── DRE ──────────────────────────────────────────────────────────────────

  /// A DRE do período, com a comparação com o período anterior de mesmo
  /// tamanho. Sem datas, o backend apura o mês corrente.
  Future<Dre> buscarDre({DateTime? dataInicio, DateTime? dataFim}) async {
    final data =
        await _client.get('/financeiro/dre${_periodo(dataInicio, dataFim)}');
    return Dre.fromJson(data as Map<String, dynamic>);
  }

  /// Receita, custos e resultado de cada mês do ano — a série do gráfico.
  Future<List<MesDre>> buscarDreMensal({int? ano}) async {
    final lista = await _client
            .get('/financeiro/dre/mensal${ano == null ? '' : '?ano=$ano'}')
        as List<dynamic>;
    return [
      for (final m in lista)
        if (m is Map<String, dynamic>) MesDre.fromJson(m),
    ];
  }

  // ── Lançamentos gerenciais ───────────────────────────────────────────────

  /// As categorias que o papel de quem está logado pode lançar.
  Future<List<CategoriaDeLancamento>> buscarCategorias() async {
    final lista = await _client.get('/financeiro/categorias') as List<dynamic>;
    return [
      for (final c in lista)
        if (c is Map<String, dynamic>) CategoriaDeLancamento.fromJson(c),
    ];
  }

  /// O que foi informado e conta no período — a mesma regra da DRE.
  Future<List<LancamentoGerencial>> listarLancamentos({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final lista = await _client
            .get('/financeiro/lancamentos${_periodo(dataInicio, dataFim)}')
        as List<dynamic>;
    return [
      for (final l in lista)
        if (l is Map<String, dynamic>) LancamentoGerencial.fromJson(l),
    ];
  }

  Future<LancamentoGerencial> criarLancamento(LancamentoGerencial l) async {
    final data = await _client.post('/financeiro/lancamentos', l.toJson());
    return LancamentoGerencial.fromJson(data as Map<String, dynamic>);
  }

  Future<LancamentoGerencial> atualizarLancamento(
      int id, LancamentoGerencial l) async {
    final data = await _client.put('/financeiro/lancamentos/$id', l.toJson());
    return LancamentoGerencial.fromJson(data as Map<String, dynamic>);
  }

  Future<void> excluirLancamento(int id) async {
    await _client.delete('/financeiro/lancamentos/$id');
  }

  // ── Apoio ────────────────────────────────────────────────────────────────

  static String _periodo(DateTime? de, DateTime? ate) {
    final partes = [
      if (de != null) 'dataInicio=${_data(de)}',
      if (ate != null) 'dataFim=${_data(ate)}',
    ];
    return partes.isEmpty ? '' : '?${partes.join('&')}';
  }

  static String _data(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
