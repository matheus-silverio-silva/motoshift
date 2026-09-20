import '../../models/carteira.dart';
import '../../models/cobranca.dart';
import '../../models/extrato_filtro.dart';
import '../../models/resumo_financeiro.dart';
import '../../models/transacao.dart';
import 'api_client.dart';

/// Uma página do extrato, com o total para a rolagem infinita saber onde parar.
typedef PaginaDoExtrato = ({List<Transacao> itens, int total});

/// Carteira: saldo, extrato, recarga, saque, resumo, fluxo e chave Pix.
class CarteiraApi {
  final ApiClient _client;

  CarteiraApi(this._client);

  // ── Saldo ────────────────────────────────────────────────────────────────

  /// Carteira do usuário, com a primeira página do extrato embutida.
  ///
  /// Esta rota existe para a tela de carteira atual. O extrato completo, com
  /// filtros e paginação, é [buscarExtrato].
  Future<Carteira> buscarCarteira(int usuarioId) async {
    final data = await _client.get('/carteira/$usuarioId');
    return Carteira.fromJson(data as Map<String, dynamic>);
  }

  /// Resumo do período: entradas, saídas, saldo, a receber e comprometido.
  Future<ResumoFinanceiro> buscarResumo({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final query = <String, String>{};
    if (dataInicio != null) query['dataInicio'] = _data(dataInicio);
    if (dataFim != null) query['dataFim'] = _data(dataFim);

    final data = await _client.get('/carteira/resumo${_query(query)}');
    return ResumoFinanceiro.fromJson(data as Map<String, dynamic>);
  }

  // ── Extrato ──────────────────────────────────────────────────────────────

  /// Uma página do extrato filtrado.
  ///
  /// Os filtros vão para a API, e não para um `where` na lista: o cliente não
  /// tem mais o extrato inteiro em mãos para filtrar.
  Future<PaginaDoExtrato> buscarExtrato({
    ExtratoFiltro filtro = const ExtratoFiltro(),
    int pagina = 0,
    int tamanho = 20,
  }) async {
    final query = {
      ...filtro.parametros,
      'pagina': '$pagina',
      'tamanho': '$tamanho',
    };
    final resposta = await _client.getPaginado('/carteira/extrato${_query(query)}');
    final itens = (resposta.dados as List<dynamic>)
        .map((e) => Transacao.fromJson(e as Map<String, dynamic>))
        .toList();
    return (itens: itens, total: resposta.total);
  }

  /// O mesmo extrato em CSV, sem paginação.
  Future<String> exportarExtratoCsv({
    ExtratoFiltro filtro = const ExtratoFiltro(),
  }) {
    final query = {...filtro.parametros, 'formato': 'csv'};
    return _client.getTexto('/carteira/extrato/exportar${_query(query)}');
  }

  /// Série de entradas e saídas para o gráfico.
  Future<List<PontoDeFluxo>> buscarFluxo({
    String agrupamento = 'dia',
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final query = <String, String>{'agrupamento': agrupamento};
    if (dataInicio != null) query['dataInicio'] = _data(dataInicio);
    if (dataFim != null) query['dataFim'] = _data(dataFim);

    final lista = await _client.get('/carteira/fluxo${_query(query)}') as List<dynamic>;
    return lista
        .map((e) => PontoDeFluxo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Recarga ──────────────────────────────────────────────────────────────

  /// Abre a cobrança Pix. Não credita nada — o saldo só entra na confirmação.
  Future<Cobranca> criarRecarga(double valor) async {
    final data = await _client.post('/carteira/recargas', {'valor': valor});
    return Cobranca.fromJson(data as Map<String, dynamic>);
  }

  /// Simula o webhook do provedor: confirma o pagamento e credita o saldo.
  Future<Cobranca> confirmarRecarga(int cobrancaId) async {
    final data =
        await _client.post('/carteira/recargas/$cobrancaId/confirmar', {});
    return Cobranca.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Cobranca>> listarCobrancas() async {
    final lista = await _client.get('/carteira/cobrancas') as List<dynamic>;
    return lista
        .map((e) => Cobranca.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Saque ────────────────────────────────────────────────────────────────

  /// Solicita o saque. A resposta diz se o gateway aceitou ou recusou —
  /// recusado, o valor volta por um estorno e o status vem `falhou`.
  Future<Cobranca> solicitarSaque(double valor) async {
    final data = await _client.post('/carteira/saques', {'valor': valor});
    return Cobranca.fromJson(data as Map<String, dynamic>);
  }

  Future<void> atualizarPix(int usuarioId, String chavePix) async {
    await _client.put('/carteira/$usuarioId/pix', {'chavePix': chavePix});
  }

  // ── Gráfico legado ───────────────────────────────────────────────────────

  /// @deprecated Ganhos por mês. Substituído por [buscarFluxo], que separa
  /// entradas de saídas e aceita outros agrupamentos. Mantido enquanto a tela
  /// de carteira antiga ainda o usa.
  Future<List<Map<String, dynamic>>> buscarGrafico(int usuarioId,
      {int meses = 6}) async {
    final list = await _client.get('/carteira/$usuarioId/grafico?meses=$meses')
        as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  // ── Apoio ────────────────────────────────────────────────────────────────

  static String _data(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Monta a query string, escapando os valores — a busca textual pode ter
  /// espaço, acento e o que mais o usuário digitar.
  static String _query(Map<String, String> parametros) {
    if (parametros.isEmpty) return '';
    final partes = parametros.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}');
    return '?${partes.join('&')}';
  }
}
