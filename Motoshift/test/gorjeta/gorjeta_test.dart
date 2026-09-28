import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/resumo_financeiro.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/avaliacao_api.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/views/avaliacao/avaliacao_screen.dart';
import 'package:moto_shift/views/avaliar_entregadores/avaliar_entregadores_screen.dart';
import 'package:moto_shift/widgets/rating_stars.dart';
import 'package:moto_shift/widgets/seletor_de_gorjeta.dart';

import '../test_helpers.dart';

/// Gorjeta no app (V17): na avaliação do entregador, o lojista escolhe; o
/// extrato, os filtros e o resumo sabem o que ela é.
void main() {
  setUpAll(setupGoldenTests);

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> darEstrelas(WidgetTester tester) async {
    final estrelas = find.descendant(
        of: find.byType(RatingStars).first, matching: find.byType(GestureDetector));
    await tester.tap(estrelas.at(4));
    await tester.pump();
  }

  group('modelo', () {
    test('os dois lados da gorjeta', () {
      final enviada = Transacao.fromJson({
        'id': 1,
        'usuarioId': 2,
        'tipo': 'bonus_enviado',
        'natureza': 'debito',
        'valor': 10,
        'status': 'concluido',
        'criadoEm': '2026-09-28T10:00:00',
      });
      expect(enviada.tipo, TipoTransacao.bonusEnviado);
      expect(enviada.tipo.label, 'Gorjeta enviada');
      expect(TipoTransacao.bonus.label, 'Gorjeta recebida');
      expect(TipoTransacao.bonusEnviado.valorApi, 'bonus_enviado');
      expect(TipoTransacao.bonusEnviado.credito, isFalse);
    });

    test('o filtro de cada papel oferece o seu lado, e só ele', () {
      final entregador = TipoTransacao.filtraveisPara(TipoUsuario.motoboy);
      final lojista = TipoTransacao.filtraveisPara(TipoUsuario.lojista);
      expect(entregador, contains(TipoTransacao.bonus));
      expect(entregador, isNot(contains(TipoTransacao.bonusEnviado)));
      expect(lojista, contains(TipoTransacao.bonusEnviado));
      expect(lojista, isNot(contains(TipoTransacao.bonus)));
    });

    test('o resumo mostra as gorjetas só quando houve alguma', () {
      final base = {
        'papel': 'prestador',
        'dataInicio': '2026-09-01',
        'dataFim': '2026-09-28',
        'disponivel': 100,
        'recebido': 115,
        'sacado': 0,
        'aReceber': 0,
      };
      final sem = ResumoFinanceiro.fromJson(base);
      final com = ResumoFinanceiro.fromJson({...base, 'gorjetas': 15});
      expect(ResumoFinanceiro.numerosPara(TipoUsuario.motoboy, sem).map((n) => n.chave),
          isNot(contains('gorjetas')));
      final numero = ResumoFinanceiro.numerosPara(TipoUsuario.motoboy, com)
          .firstWhere((n) => n.chave == 'gorjetas');
      expect(numero.rotulo, 'Gorjetas recebidas');
      expect(numero.valor, 15);
    });
  });

  group('seletor', () {
    testWidgets('sugestões, outro valor e o teto', (tester) async {
      double? escolhido = -99;
      await pumpGolden(tester,
          child: Scaffold(body: SeletorDeGorjeta(onMudou: (v) => escolhido = v)));

      await tester.tap(find.byKey(const Key('gorjeta-10')));
      await tester.pump();
      expect(escolhido, 10);

      await tester.tap(find.byKey(const Key('gorjeta-outro')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('gorjeta-outro-valor')), '60');
      await tester.pump();
      expect(escolhido, isNull);
      expect(find.text('A gorjeta vai até R\$ 50.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('gorjeta-outro-valor')), '7,50');
      await tester.pump();
      expect(escolhido, 7.5);

      await tester.tap(find.byKey(const Key('gorjeta-nenhuma')));
      await tester.pump();
      expect(escolhido, isNull);
    });
  });

  group('avaliação de um entregador', () {
    const args = AvaliacaoArgs(
        turnoId: 501, avaliadorId: 2, avaliadoId: 1, nomeAvaliado: 'Ricardo Souza');

    testWidgets('o lojista avalia e dá R\$ 10 de gorjeta', (tester) async {
      final api = _ApiDeGorjeta();
      await pumpGolden(tester,
          child: const AvaliacaoScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: args,
          apiFake: api);

      await darEstrelas(tester);
      await tester.ensureVisible(find.byKey(const Key('gorjeta-10')));
      await tester.tap(find.byKey(const Key('gorjeta-10')));
      await tester.pump();
      await tester.ensureVisible(find.text('Enviar avaliação'));
      await tester.tap(find.text('Enviar avaliação'));
      await esperar(tester);

      expect(api.avaliacoesFalsas.enviadas, hasLength(1));
      expect(api.turnosFalsos.gorjetas.single, (501, 1, 10.0));
      expect(find.text('Avaliação e gorjeta de R\$ 10 enviadas!'), findsOneWidget);
    });

    testWidgets('sem saldo: a avaliação fica, e o motivo da gorjeta é dito', (tester) async {
      final api = _ApiDeGorjeta()
        ..turnosFalsos.recusa = const ApiException(422,
            'Saldo insuficiente para a gorjeta de R\$ 10,00: você tem R\$ 3,00 disponível.');
      await pumpGolden(tester,
          child: const AvaliacaoScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: args,
          apiFake: api);

      await darEstrelas(tester);
      await tester.ensureVisible(find.byKey(const Key('gorjeta-10')));
      await tester.tap(find.byKey(const Key('gorjeta-10')));
      await tester.pump();
      await tester.ensureVisible(find.text('Enviar avaliação'));
      await tester.tap(find.text('Enviar avaliação'));
      await esperar(tester);

      expect(api.avaliacoesFalsas.enviadas, hasLength(1));
      expect(find.textContaining('mas a gorjeta não: Saldo insuficiente'), findsOneWidget);
    });

    testWidgets('sem gorjeta escolhida, nada é cobrado', (tester) async {
      final api = _ApiDeGorjeta();
      await pumpGolden(tester,
          child: const AvaliacaoScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: args,
          apiFake: api);

      await darEstrelas(tester);
      await tester.scrollUntilVisible(find.text('Enviar avaliação'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Enviar avaliação'));
      await esperar(tester);

      expect(api.turnosFalsos.gorjetas, isEmpty);
    });

    testWidgets('o entregador avaliando a loja não vê gorjeta', (tester) async {
      await pumpGolden(tester,
          child: const AvaliacaoScreen(),
          argumentos: const AvaliacaoArgs(
              turnoId: 501, avaliadorId: 1, avaliadoId: 2, nomeAvaliado: 'Hamburgueria'));

      expect(find.byType(SeletorDeGorjeta), findsNothing);
    });
  });

  testWidgets('turno multi-vaga: cada entregador tem a sua gorjeta', (tester) async {
    final api = _ApiDeGorjeta();
    await pumpGolden(tester,
        child: const AvaliarEntregadoresScreen(),
        tipoUsuario: TipoUsuario.lojista,
        argumentos: const AvaliarEntregadoresArgs(turnoId: 501, tituloTurno: 'Turno Noite'),
        apiFake: api);

    await darEstrelas(tester);
    await tester.ensureVisible(find.byKey(const Key('gorjeta-20')));
    await tester.tap(find.byKey(const Key('gorjeta-20')));
    await tester.pump();
    await tester.ensureVisible(find.text('Enviar avaliação'));
    await tester.tap(find.text('Enviar avaliação'));
    await esperar(tester);

    expect(api.turnosFalsos.gorjetas.single, (501, 1, 20.0));
    expect(find.text('Ricardo Souza avaliado, com gorjeta.'), findsOneWidget);
  });
}

class _TurnosDeGorjeta extends FakeTurnoApi {
  final List<(int, int, double)> gorjetas = [];
  ApiException? recusa;

  @override
  Future<void> darGorjeta(int turnoId, int entregadorId, double valor) async {
    final r = recusa;
    if (r != null) throw r;
    gorjetas.add((turnoId, entregadorId, valor));
  }
}

class _AvaliacoesQueGuardam extends FakeAvaliacaoApi {
  final List<Map<String, dynamic>> enviadas = [];

  @override
  Future<Map<String, dynamic>> registrarAvaliacao(Map<String, dynamic> corpo) async {
    enviadas.add(corpo);
    return corpo;
  }
}

class _ApiDeGorjeta extends FakeApiService {
  _ApiDeGorjeta() : super(tipoUsuario: TipoUsuario.lojista);

  final _TurnosDeGorjeta turnosFalsos = _TurnosDeGorjeta();
  final _AvaliacoesQueGuardam avaliacoesFalsas = _AvaliacoesQueGuardam();

  @override
  TurnoApi get turnos => turnosFalsos;

  @override
  AvaliacaoApi get avaliacoes => avaliacoesFalsas;
}
