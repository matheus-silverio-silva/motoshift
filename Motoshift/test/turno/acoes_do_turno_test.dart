import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/meus_turnos/turnos_cards.dart';
import 'package:moto_shift/widgets/acoes_do_turno.dart';

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
