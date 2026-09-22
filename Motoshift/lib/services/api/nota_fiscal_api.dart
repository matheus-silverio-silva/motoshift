import '../../models/informe_anual.dart';
import '../../models/nota_fiscal.dart';
import '../../models/nota_fiscal_filtro.dart';
import 'api_client.dart';

/// Notas fiscais de serviço dos turnos.
///
/// Nenhum método recebe o id do usuário: o backend o lê do token. A mesma
/// chamada serve ao lojista e ao entregador — muda o lado em que cada um
/// aparece no documento, não a rota.
class NotaFiscalApi {
  final ApiClient _client;

  NotaFiscalApi(this._client);

  /// Notas em que o usuário é prestador ou tomador, da competência mais
  /// recente para a mais antiga.
  ///
  /// Sem [pagina], vem a lista inteira — é o contrato antigo, que continua
  /// valendo. Com [pagina], a resposta ainda é um array e o total vem no
  /// header `X-Total-Count`, como no extrato.
  Future<PaginaDeNotas> listar({
    NotaFiscalFiltro filtro = const NotaFiscalFiltro(),
    int? pagina,
    int tamanho = 20,
  }) async {
    final query = <String>[
      filtro.toQuery(),
      if (pagina != null) 'pagina=$pagina&tamanho=$tamanho',
    ].where((q) => q.isNotEmpty).join('&');

    final r = await _client
        .getPaginado('/notas-fiscais${query.isEmpty ? '' : '?$query'}');
    final lista = (r.dados as List<dynamic>)
        .map((e) => NotaFiscal.fromJson(e as Map<String, dynamic>))
        .toList();
    return PaginaDeNotas(notas: lista, total: r.total);
  }

  /// Informe anual SIMULADO: rendimentos do entregador ou serviços tomados
  /// pelo lojista, por contraparte e por mês.
  Future<InformeAnual> resumo({int? ano}) async {
    final data = await _client
        .get('/notas-fiscais/resumo${ano == null ? '' : '?ano=$ano'}');
    return InformeAnual.fromJson(data as Map<String, dynamic>);
  }

  /// O mesmo informe em CSV, pronto para salvar.
  Future<String> exportarResumo({int? ano}) {
    return _client
        .getTexto('/notas-fiscais/resumo/exportar${ano == null ? '' : '?ano=$ano'}');
  }

  /// Turnos finalizados que ainda não geraram nota.
  Future<List<NotaFiscalPendente>> pendentes() async {
    final list = await _client.get('/notas-fiscais/pendentes') as List<dynamic>;
    return list
        .map((e) => NotaFiscalPendente.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Emite a nota do turno. [prestadorId] só é necessário quando quem emite é
  /// o lojista de um turno com mais de um entregador.
  Future<NotaFiscal> emitir(int turnoId, {int? prestadorId}) async {
    final data = await _client.post('/notas-fiscais', {
      'turnoId': turnoId,
      if (prestadorId != null) 'prestadorId': prestadorId,
    });
    return NotaFiscal.fromJson(data as Map<String, dynamic>);
  }

  Future<NotaFiscal> buscar(int id) async {
    final data = await _client.get('/notas-fiscais/$id');
    return NotaFiscal.fromJson(data as Map<String, dynamic>);
  }

  /// Cancelamento é do prestador; o backend recusa o pedido do tomador.
  Future<NotaFiscal> cancelar(int id, {String? motivo}) async {
    final data = await _client.put('/notas-fiscais/$id/cancelar', {
      if (motivo != null) 'motivo': motivo,
    });
    return NotaFiscal.fromJson(data as Map<String, dynamic>);
  }
}

/// Uma página de notas e quantas existem no filtro — o total vem do header,
/// para a tela saber quando parar de pedir.
class PaginaDeNotas {
  const PaginaDeNotas({required this.notas, required this.total});

  final List<NotaFiscal> notas;
  final int total;
}
