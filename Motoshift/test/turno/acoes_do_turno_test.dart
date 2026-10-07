import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/views/meus_turnos/turnos_cards.dart';
import 'package:moto_shift/widgets/acoes_do_turno.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// As ações do turno seguem o que o backend aceitaria — nem mais, nem menos.
///
/// "Finalizar" aparecia em qualquer turno com entregador: o entregador
/// aceitava um turno de amanhã, tocava o botão e recebia na hora. Agora ele
/// só existe quando `TurnoService.finalizar` passaria: turno começado e
/// alguém com check-in.
void main() {
  setUpAll(setupGoldenTests);

  final agora = DateTime(2026, 10, 5, 15, 0);

  Turno turno({
    required DateTime inicio,
    bool algumCheckin = false,
    StatusTurno status = StatusTurno.aceito,
  }) =>
      Turno(
        id: 601,
        lojistId: 2,
        motoboyId: 1,
        titulo: 'Turno Tarde — Hamburgueria',
        regiao: 'Água Verde, Curitiba',
        dataInicio: inicio,
        dataFim: inicio.add(const Duration(hours: 4)),
        valorEstimado: 120,
        raioEntregaKm: 8,
        status: status,
        algumCheckin: algumCheckin,
      );

  group('Turno.podeSerFinalizado', () {
    test('turno de amanhã não finaliza, nem com check-in', () {
      final t = turno(
          inicio: agora.add(const Duration(days: 1)), algumCheckin: true);
      expect(t.podeSerFinalizado(agora: agora), isFalse);
    });

    test('turno que começou sem ninguém chegar não finaliza', () {
      final t = turno(inicio: agora.subtract(const Duration(hours: 1)));
      expect(t.podeSerFinalizado(agora: agora), isFalse);
    });

    test('começou e alguém fez check-in: finaliza', () {
      final t = turno(
          inicio: agora.subtract(const Duration(hours: 1)), algumCheckin: true);
      expect(t.podeSerFinalizado(agora: agora), isTrue);
    });

    test('no minuto do início já vale', () {
      final t = turno(inicio: agora, algumCheckin: true);
      expect(t.podeSerFinalizado(agora: agora), isTrue);
    });

    test('turno encerrado não tem o que finalizar', () {
      for (final status in [
        StatusTurno.finalizado,
        StatusTurno.cancelado,
        StatusTurno.expirado,
      ]) {
        final t = turno(
          inicio: agora.subtract(const Duration(hours: 5)),
          algumCheckin: true,
          status: status,
        );
        expect(t.podeSerFinalizado(agora: agora), isFalse, reason: status.name);
      }
    });

    test('algumCheckin vem do JSON do backend; ausente é false', () {
      final base = {
        'id': 1,
        'lojistId': 2,
        'titulo': 'Turno',
        'regiao': 'Batel',
        'dataInicio': '2026-10-05T14:00:00',
        'dataFim': '2026-10-05T18:00:00',
        'valorEstimado': 100,
        'raioEntregaKm': 8,
        'status': 'aceito',
      };
      expect(Turno.fromJson(base).algumCheckin, isFalse);
      expect(Turno.fromJson({...base, 'algumCheckin': true}).algumCheckin,
          isTrue);
    });
  });

  group('"Finalizar turno"', () {
    // O relógio do widget é o real: início bem no futuro ou bem no passado,
    // para o teste não depender da hora em que a suíte roda.
    final ontem = DateTime.now().subtract(const Duration(days: 1));
    final amanha = DateTime.now().add(const Duration(days: 1));

    for (final papel in [TipoUsuario.lojista, TipoUsuario.motoboy]) {
      testWidgets('não aparece no turno de amanhã (${papel.name})',
          (tester) async {
        await pumpGolden(tester,
            child: Scaffold(
                body: AcoesDoTurno(
                    turno: turno(inicio: amanha, algumCheckin: true))),
            tipoUsuario: papel);
        expect(find.byKey(const Key('acao-finalizar')), findsNothing);
      });

      testWidgets('não aparece sem check-in (${papel.name})', (tester) async {
        await pumpGolden(tester,
            child: Scaffold(body: AcoesDoTurno(turno: turno(inicio: ontem))),
            tipoUsuario: papel);
        expect(find.byKey(const Key('acao-finalizar')), findsNothing);
      });
    }

    testWidgets('aparece para o lojista no turno começado e com check-in',
        (tester) async {
      await pumpGolden(tester,
          child: Scaffold(
              body: AcoesDoTurno(
                  turno: turno(
                      inicio: ontem,
                      algumCheckin: true,
                      status: StatusTurno.emAndamento))),
          tipoUsuario: TipoUsuario.lojista);
      expect(find.byKey(const Key('acao-finalizar')), findsOneWidget);
    });
  });

  // Sair do turno: uma ação para cada lado (SCRUM-26). Era "Cancelar turno"
  // para os dois, e a penalidade caía no entregador mesmo quando quem
  // cancelava era a loja.
  group('cancelar (a loja) e desistir (o entregador)', () {
    final emDoisDias = DateTime.now().add(const Duration(days: 2));
    final em20Min = DateTime.now().add(const Duration(minutes: 20));

    /// O entregador com o turno entre os dele — é o que faz o widget tratá-lo
    /// como inscrito, e não como alguém olhando uma vaga.
    Future<_ApiDeDesistencia> comoEntregadorInscrito(
        WidgetTester tester, Turno t) async {
      final api = _ApiDeDesistencia(t);
      await pumpGolden(tester,
          child: Scaffold(body: AcoesDoTurno(turno: t)), apiFake: api);
      final contexto = tester.element(find.byType(AcoesDoTurno));
      await contexto.read<TurnoProvider>().carregarMeusTurnos(1);
      await tester.pump();
      return api;
    }

    testWidgets('o lojista vê "Cancelar turno" — e o aviso de que ninguém é penalizado',
        (tester) async {
      await pumpGolden(tester,
          child: Scaffold(body: AcoesDoTurno(turno: turno(inicio: em20Min))),
          tipoUsuario: TipoUsuario.lojista);

      expect(find.byKey(const Key('acao-cancelar')), findsOneWidget);
      expect(find.byKey(const Key('acao-desistir')), findsNothing);

      await tester.tap(find.byKey(const Key('acao-cancelar')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhum entregador é penalizado'), findsOneWidget);
      // O texto antigo punha a penalidade do entregador na conta da loja.
      expect(find.textContaining('desconta 0,5'), findsNothing);
    });

    testWidgets('o entregador inscrito vê "Desistir da vaga", nunca "Cancelar turno"',
        (tester) async {
      await comoEntregadorInscrito(tester, turno(inicio: emDoisDias));

      expect(find.byKey(const Key('acao-desistir')), findsOneWidget);
      expect(find.byKey(const Key('acao-cancelar')), findsNothing);
    });

    testWidgets('com folga, o diálogo diz que desistir não muda o score',
        (tester) async {
      await comoEntregadorInscrito(tester, turno(inicio: emDoisDias));

      await tester.tap(find.byKey(const Key('acao-desistir')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('desistir-sem-penalidade')), findsOneWidget);
      expect(find.textContaining('não muda o seu score'), findsOneWidget);
    });

    testWidgets('a menos de 1 hora, o diálogo avisa do 0,5 antes de confirmar',
        (tester) async {
      await comoEntregadorInscrito(tester, turno(inicio: em20Min));

      await tester.tap(find.byKey(const Key('acao-desistir')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('desistir-com-penalidade')), findsOneWidget);
      expect(find.textContaining('desconta 0,5 do seu score'), findsOneWidget);
    });

    testWidgets('confirmar chama /desistir e o turno sai dos turnos do entregador',
        (tester) async {
      var mudou = false;
      final t = turno(inicio: emDoisDias);
      final api = _ApiDeDesistencia(t);
      await pumpGolden(tester,
          child: Scaffold(
              body: AcoesDoTurno(turno: t, onMudou: () => mudou = true)),
          apiFake: api);
      final provider =
          tester.element(find.byType(AcoesDoTurno)).read<TurnoProvider>();
      await provider.carregarMeusTurnos(1);
      await tester.pump();

      await tester.tap(find.byKey(const Key('acao-desistir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar-desistir')));
      await tester.pumpAndSettle();

      expect(api.turnosFalsos.desistencias, [601]);
      expect(api.turnosFalsos.cancelamentos, isEmpty);
      expect(provider.meusTurnos.any((x) => x.id == 601), isFalse);
      // A vaga reabriu: o turno volta para os disponíveis.
      expect(provider.turnosDisponiveis.any((x) => x.id == 601), isTrue);
      expect(find.text('Você desistiu da vaga.'), findsOneWidget);
      expect(mudou, isTrue);
    });

    testWidgets('"Voltar" no diálogo não desiste de nada', (tester) async {
      final api =
          await comoEntregadorInscrito(tester, turno(inicio: emDoisDias));

      await tester.tap(find.byKey(const Key('acao-desistir')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();

      expect(api.turnosFalsos.desistencias, isEmpty);
    });

    testWidgets('em andamento, nem a loja cancela nem o entregador desiste',
        (tester) async {
      final t = turno(
          inicio: DateTime.now().subtract(const Duration(minutes: 10)),
          algumCheckin: true,
          status: StatusTurno.emAndamento);
      await comoEntregadorInscrito(tester, t);
      expect(find.byKey(const Key('acao-desistir')), findsNothing);
      expect(find.byKey(const Key('acao-cancelar')), findsNothing);
    });
  });

  group('card do turno em andamento (entregador)', () {
    Widget card(Turno t) => MaterialApp(
          home: Scaffold(
            body: TurnoAtivoCard(
                turno: t, agora: agora, onConfirmarConclusao: () {}),
          ),
        );

    testWidgets('com check-in e turno começado, oferece a conclusão',
        (tester) async {
      await tester.pumpWidget(card(turno(
        inicio: agora.subtract(const Duration(minutes: 20)),
        algumCheckin: true,
        status: StatusTurno.emAndamento,
      )));
      expect(find.text('Confirmar conclusão'), findsOneWidget);
      expect(find.byKey(const Key('conclusao-indisponivel')), findsNothing);
    });

    testWidgets(
        'check-in feito antes do início: diz a partir de quando, sem botão',
        (tester) async {
      await tester.pumpWidget(card(turno(
        inicio: agora.add(const Duration(minutes: 20)),
        algumCheckin: true,
        status: StatusTurno.emAndamento,
      )));
      expect(find.text('Confirmar conclusão'), findsNothing);
      expect(find.textContaining('depois das 15:20'), findsOneWidget);
    });
  });
}

/// O turno do teste entre os turnos do entregador, e o registro do que foi
/// pedido ao backend.
class _TurnosDeDesistencia extends FakeTurnoApi {
  _TurnosDeDesistencia(this.meu);

  final Turno meu;
  final List<int> desistencias = [];
  final List<int> cancelamentos = [];

  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) async => [meu];

  /// Como o backend responde: a vaga reabriu, o turno ficou sem entregador.
  @override
  Future<Turno> desistirDaVaga(int turnoId) async {
    desistencias.add(turnoId);
    return Turno(
      id: meu.id,
      lojistId: meu.lojistId,
      titulo: meu.titulo,
      regiao: meu.regiao,
      dataInicio: meu.dataInicio,
      dataFim: meu.dataFim,
      valorEstimado: meu.valorEstimado,
      raioEntregaKm: meu.raioEntregaKm,
      status: StatusTurno.aberto,
    );
  }

  @override
  Future<Turno> cancelarTurno(int turnoId) async {
    cancelamentos.add(turnoId);
    return meu;
  }
}

class _ApiDeDesistencia extends FakeApiService {
  _ApiDeDesistencia(Turno meu) : turnosFalsos = _TurnosDeDesistencia(meu);

  final _TurnosDeDesistencia turnosFalsos;

  @override
  TurnoApi get turnos => turnosFalsos;
}
