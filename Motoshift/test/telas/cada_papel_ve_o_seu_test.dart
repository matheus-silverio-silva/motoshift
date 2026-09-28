// Cada papel vê só o que é dele.
//
// O entregador presta serviço, o lojista contrata. Nenhuma tela financeira
// mostra a um deles um número, um filtro ou um rótulo que só faz sentido para
// o outro — nem zerado. Estes testes prendem as telas que já erraram nisso: o
// filtro do extrato (o entregador via "Recarga" e "Reserva") e os cartões dos
// relatórios ("Comprometido R$ 0,00" para o entregador, "A receber R$ 0,00"
// para o lojista, e "Entradas/Saídas" dizendo coisas diferentes para cada um).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/resumo_financeiro.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/carteira_api.dart';
import 'package:moto_shift/views/extrato/extrato_screen.dart';
import 'package:moto_shift/views/relatorios_financeiros/relatorios_financeiros_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  group('A lista de tipos por papel', () {
    test('entregador e lojista só compartilham o estorno', () {
      final entregador = TipoTransacao.filtraveisPara(TipoUsuario.motoboy);
      final lojista = TipoTransacao.filtraveisPara(TipoUsuario.lojista);

      expect(entregador, [
        TipoTransacao.pagamentoRecebido,
        TipoTransacao.saque,
        TipoTransacao.estorno,
        TipoTransacao.retencaoIss,
        TipoTransacao.retencaoIrrf,
      ]);
      expect(lojista, [
        TipoTransacao.recarga,
        TipoTransacao.reserva,
        TipoTransacao.liberacaoReserva,
        TipoTransacao.pagamentoEnviado,
        TipoTransacao.estorno,
      ]);
      expect(entregador.toSet().intersection(lojista.toSet()),
          {TipoTransacao.estorno});
    });
  });

  group('Filtro do extrato', () {
    testWidgets('o entregador não vê recarga, reserva nem pagamento enviado',
        (tester) async {
      await _abrirFiltros(tester, TipoUsuario.motoboy);

      for (final t in ['pagamentoRecebido', 'saque', 'estorno', 'retencaoIss']) {
        expect(find.byKey(Key('filtro-tipo-$t')), findsOneWidget, reason: t);
      }
      for (final t in ['recarga', 'reserva', 'liberacaoReserva', 'pagamentoEnviado']) {
        expect(find.byKey(Key('filtro-tipo-$t')), findsNothing, reason: t);
      }
    });

    testWidgets('o lojista não vê pagamento recebido nem saque', (tester) async {
      await _abrirFiltros(tester, TipoUsuario.lojista);

      for (final t in ['recarga', 'reserva', 'liberacaoReserva', 'pagamentoEnviado', 'estorno']) {
        expect(find.byKey(Key('filtro-tipo-$t')), findsOneWidget, reason: t);
      }
      for (final t in ['pagamentoRecebido', 'saque', 'retencaoIss', 'retencaoIrrf']) {
        expect(find.byKey(Key('filtro-tipo-$t')), findsNothing, reason: t);
      }
    });
  });

  group('Relatórios', () {
    testWidgets('entregador: recebido, sacado, disponível e a receber', (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.motoboy,
          child: RelatoriosFinanceirosScreen(agora: dataAncoraGolden));

      for (final k in ['recebido', 'sacado', 'disponivel', 'a-receber']) {
        expect(find.byKey(Key('relatorio-$k')), findsOneWidget, reason: k);
      }
      for (final k in ['recarregado', 'pago', 'devolvido', 'comprometido',
          'entradas', 'saidas', 'liquido']) {
        expect(find.byKey(Key('relatorio-$k')), findsNothing, reason: k);
      }
      // Sem retenção na fonte, não há "retido" — nem R$ 0,00.
      expect(find.byKey(const Key('relatorio-retencoes')), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const Key('relatorio-recebido')),
              matching: find.textContaining('620,00')),
          findsOneWidget);
    });

    testWidgets('entregador com retenção na fonte vê o que foi retido',
        (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.motoboy,
          apiFake: _ApiComResumo(fakeResumoFinanceiro(retencoes: 31)),
          child: RelatoriosFinanceirosScreen(agora: dataAncoraGolden));

      expect(
          find.descendant(
              of: find.byKey(const Key('relatorio-retencoes')),
              matching: find.textContaining('31,00')),
          findsOneWidget);
    });

    testWidgets('lojista: recarregado, pago, devolvido, disponível e comprometido',
        (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.lojista,
          child: RelatoriosFinanceirosScreen(agora: dataAncoraGolden));

      for (final k in ['recarregado', 'pago', 'devolvido', 'disponivel', 'comprometido']) {
        expect(find.byKey(Key('relatorio-$k')), findsOneWidget, reason: k);
      }
      for (final k in ['recebido', 'sacado', 'a-receber', 'retencoes',
          'entradas', 'saidas', 'liquido']) {
        expect(find.byKey(Key('relatorio-$k')), findsNothing, reason: k);
      }
      expect(find.text('Comprometido em turnos'), findsOneWidget);
      expect(find.text('A receber'), findsNothing);
    });
  });

  group('Resumo vindo da API', () {
    test('campo do outro papel ausente vira nulo, não zero', () {
      final r = ResumoFinanceiro.fromJson({
        'papel': 'tomador',
        'dataInicio': '2026-09-01',
        'dataFim': '2026-09-28',
        'disponivel': 100,
        'recarregado': 500,
        'pagoAEntregadores': 360,
        'devolvido': 40,
        'bloqueado': 0,
        'comprometido': 0,
        'reservasAbertas': [],
        'porTipo': [],
      });

      expect(r.souTomador, isTrue);
      expect(r.recarregado, 500);
      expect(r.comprometido, 0);
      expect(r.recebido, isNull);
      expect(r.aReceber, isNull);
      expect(r.sacado, isNull);
    });
  });
}

Future<void> _abrirFiltros(WidgetTester tester, TipoUsuario papel) async {
  await pumpGolden(tester,
      tipoUsuario: papel, child: ExtratoScreen(agora: dataAncoraGolden));
  await tester.tap(find.byKey(const Key('extrato-abrir-filtros')));
  await tester.pumpAndSettle();
}

class _ApiComResumo extends FakeApiService {
  _ApiComResumo(this.resumo);

  final ResumoFinanceiro resumo;

  @override
  CarteiraApi get carteira => _CarteiraComResumo(resumo);
}

class _CarteiraComResumo extends FakeCarteiraApi {
  _CarteiraComResumo(this.resumo);

  final ResumoFinanceiro resumo;

  @override
  Future<ResumoFinanceiro> buscarResumo({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async =>
      resumo;
}
