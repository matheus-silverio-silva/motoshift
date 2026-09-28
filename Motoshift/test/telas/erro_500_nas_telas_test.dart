// Um 500 nas telas de dinheiro: carteira, extrato, relatórios, saldo do
// lojista e informe anual.
//
// O que estes testes prendem: o 500 aparece como erro com "Tentar novamente"
// — nunca tela vazia, spinner eterno ou "nenhum lançamento" —, e tocar em
// "Tentar novamente" refaz a carga e a tela volta. Relatórios, extrato e
// saldo do lojista só tinham o puxar para atualizar, que no navegador
// ninguém descobre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/carteira.dart';
import 'package:moto_shift/models/extrato_filtro.dart';
import 'package:moto_shift/models/informe_anual.dart';
import 'package:moto_shift/models/resumo_financeiro.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/carteira_api.dart';
import 'package:moto_shift/services/api/nota_fiscal_api.dart';
import 'package:moto_shift/views/carteira/carteira_screen.dart';
import 'package:moto_shift/views/extrato/extrato_screen.dart';
import 'package:moto_shift/views/notas_fiscais/notas_fiscais_screen.dart';
import 'package:moto_shift/views/relatorios_financeiros/relatorios_financeiros_screen.dart';
import 'package:moto_shift/views/saldo_lojista/saldo_lojista_screen.dart';

import '../test_helpers.dart';

/// O que o ApiClient lança para qualquer 5xx.
const _erro500 = ApiException(500, 'Erro interno, tente novamente');

/// A carteira que responde 500 até [falhar] virar falso.
class _CarteiraQueFalha extends FakeCarteiraApi {
  _CarteiraQueFalha({super.papel});

  bool falhar = true;

  @override
  Future<Carteira> buscarCarteira(int motoboyId) =>
      falhar ? Future.error(_erro500) : super.buscarCarteira(motoboyId);

  @override
  Future<ResumoFinanceiro> buscarResumo({DateTime? dataInicio, DateTime? dataFim}) =>
      falhar
          ? Future.error(_erro500)
          : super.buscarResumo(dataInicio: dataInicio, dataFim: dataFim);

  @override
  Future<PaginaDoExtrato> buscarExtrato({
    ExtratoFiltro filtro = const ExtratoFiltro(),
    int pagina = 0,
    int tamanho = 20,
  }) =>
      falhar
          ? Future.error(_erro500)
          : super.buscarExtrato(filtro: filtro, pagina: pagina, tamanho: tamanho);

  @override
  Future<List<PontoDeFluxo>> buscarFluxo({
    String agrupamento = 'dia',
    DateTime? dataInicio,
    DateTime? dataFim,
  }) =>
      falhar
          ? Future.error(_erro500)
          : super.buscarFluxo(
              agrupamento: agrupamento, dataInicio: dataInicio, dataFim: dataFim);
}

/// O informe anual que responde 500 até [falhar] virar falso.
class _NotasQueFalham extends FakeNotaFiscalApi {
  bool falhar = true;

  @override
  Future<InformeAnual> resumo({int? ano}) =>
      falhar ? Future.error(_erro500) : super.resumo(ano: ano);
}

class _ApiQueFalha extends FakeApiService {
  _ApiQueFalha({super.tipoUsuario}) : _carteira = _CarteiraQueFalha(papel: tipoUsuario);

  final _CarteiraQueFalha _carteira;
  final _NotasQueFalham _notas = _NotasQueFalham();

  @override
  CarteiraApi get carteira => _carteira;

  @override
  NotaFiscalApi get notasFiscais => _notas;

  /// O backend volta: as próximas chamadas respondem.
  void voltar() {
    _carteira.falhar = false;
    _notas.falhar = false;
  }
}

void main() {
  setUpAll(setupGoldenTests);

  testWidgets('carteira: o 500 vira erro com "Tentar novamente", e a tela volta',
      (tester) async {
    final api = _ApiQueFalha();
    await pumpGolden(tester, child: const CarteiraScreen(), apiFake: api);

    expect(find.text('Erro interno, tente novamente'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    api.voltar();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Erro interno, tente novamente'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets('extrato: o 500 não vira "nenhum lançamento", e tentar de novo traz a lista',
      (tester) async {
    final api = _ApiQueFalha();
    await pumpGolden(tester, child: const ExtratoScreen(), apiFake: api);

    expect(find.text('Erro interno, tente novamente'), findsOneWidget);
    expect(find.byKey(const Key('extrato-vazio')), findsNothing);

    api.voltar();
    await tester.tap(find.byKey(const Key('extrato-tentar-novamente')));
    await tester.pumpAndSettle();

    expect(find.text('Erro interno, tente novamente'), findsNothing);
    expect(find.byKey(const Key('extrato-vazio')), findsNothing);
    expect(find.textContaining('Recarga via Pix'), findsWidgets);
  });

  testWidgets('relatórios: o 500 tem "Tentar novamente", e a tela volta com os números',
      (tester) async {
    final api = _ApiQueFalha();
    await pumpGolden(tester, child: const RelatoriosFinanceirosScreen(), apiFake: api);

    expect(find.text('Erro interno, tente novamente'), findsOneWidget);

    api.voltar();
    await tester.tap(find.byKey(const Key('relatorio-tentar-novamente')));
    await tester.pumpAndSettle();

    expect(find.text('Erro interno, tente novamente'), findsNothing);
    expect(find.byKey(const Key('relatorio-tentar-novamente')), findsNothing);
  });

  testWidgets('saldo do lojista: sem saldo carregado, "Tentar novamente" devolve o "Adicionar saldo"',
      (tester) async {
    final api = _ApiQueFalha(tipoUsuario: TipoUsuario.lojista);
    await pumpGolden(tester,
        tipoUsuario: TipoUsuario.lojista, child: const SaldoLojistaScreen(), apiFake: api);

    expect(find.text('Erro interno, tente novamente'), findsOneWidget);
    expect(find.byKey(const Key('saldo-lojista-adicionar')), findsNothing);

    api.voltar();
    await tester.tap(find.byKey(const Key('saldo-lojista-tentar-novamente')));
    await tester.pumpAndSettle();

    expect(find.text('Erro interno, tente novamente'), findsNothing);
    expect(find.byKey(const Key('saldo-lojista-adicionar')), findsOneWidget);
  });

  testWidgets('informe anual: o 500 vira "Informe indisponível" com "Tentar novamente"',
      (tester) async {
    final api = _ApiQueFalha();
    await pumpGolden(tester, child: const NotasFiscaisScreen(), apiFake: api);

    await tester.tap(find.text('Informe anual'));
    await tester.pumpAndSettle();

    expect(find.text('Informe indisponível'), findsOneWidget);
    expect(find.byKey(const Key('informe-total')), findsNothing);

    api.voltar();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Informe indisponível'), findsNothing);
    expect(find.byKey(const Key('informe-total')), findsOneWidget);
  });
}
