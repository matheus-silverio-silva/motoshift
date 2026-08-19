// Testes da seleção de "Próximos turnos".
//
// Cobre o defeito em que a home do lojista listava turnos Cancelado e
// Finalizado numa seção chamada "Próximos turnos": a tela usava a lista crua
// do provider, que vem do backend sem filtro nem ordenação.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';

Turno _turno({
  required int id,
  required StatusTurno status,
  required Duration inicioEm,
  Duration? duracao,
}) {
  final inicio = DateTime.now().add(inicioEm);
  return Turno(
    id: id,
    lojistId: 1,
    titulo: 'Turno $id',
    regiao: 'Centro',
    dataInicio: inicio,
    dataFim: inicio.add(duracao ?? const Duration(hours: 4)),
    valorEstimado: 100,
    raioEntregaKm: 5,
    status: status,
  );
}

void main() {
  group('TurnosFiltros.proximos()', () {
    test('remove turnos cancelados e finalizados', () {
      final turnos = [
        _turno(id: 1, status: StatusTurno.aberto, inicioEm: const Duration(days: 1)),
        _turno(id: 2, status: StatusTurno.cancelado, inicioEm: const Duration(days: 2)),
        _turno(id: 3, status: StatusTurno.finalizado, inicioEm: const Duration(days: 3)),
        _turno(id: 4, status: StatusTurno.aceito, inicioEm: const Duration(days: 4)),
      ];

      expect(turnos.proximos().map((t) => t.id), [1, 4]);
    });

    test('remove turnos que já terminaram, mesmo com status ativo', () {
      final turnos = [
        // Aceito mas ficou para trás: não é "próximo".
        _turno(id: 1, status: StatusTurno.aceito, inicioEm: const Duration(days: -5)),
        _turno(id: 2, status: StatusTurno.aberto, inicioEm: const Duration(days: 1)),
      ];

      expect(turnos.proximos().map((t) => t.id), [2]);
    });

    test('mantém turno em andamento — começou, mas ainda não terminou', () {
      final turnos = [
        _turno(
          id: 1,
          status: StatusTurno.emAndamento,
          inicioEm: const Duration(hours: -1),
          duracao: const Duration(hours: 4),
        ),
      ];

      expect(turnos.proximos().map((t) => t.id), [1]);
    });

    test('ordena por data de início ascendente', () {
      final turnos = [
        _turno(id: 1, status: StatusTurno.aberto, inicioEm: const Duration(days: 7)),
        _turno(id: 2, status: StatusTurno.aceito, inicioEm: const Duration(days: 1)),
        _turno(id: 3, status: StatusTurno.aberto, inicioEm: const Duration(days: 3)),
      ];

      expect(turnos.proximos().map((t) => t.id), [2, 3, 1]);
    });

    test('lista vazia quando todos já terminaram', () {
      final turnos = [
        _turno(id: 1, status: StatusTurno.finalizado, inicioEm: const Duration(days: -2)),
        _turno(id: 2, status: StatusTurno.cancelado, inicioEm: const Duration(days: -1)),
      ];

      expect(turnos.proximos(), isEmpty);
    });

    test('não altera a lista de origem', () {
      final turnos = [
        _turno(id: 1, status: StatusTurno.aberto, inicioEm: const Duration(days: 7)),
        _turno(id: 2, status: StatusTurno.cancelado, inicioEm: const Duration(days: 1)),
      ];

      turnos.proximos();

      expect(turnos.map((t) => t.id), [1, 2]);
    });
  });

  group('StatusTurno.ativo', () {
    test('ativo para aberto, aceito e em andamento', () {
      expect(StatusTurno.aberto.ativo, isTrue);
      expect(StatusTurno.aceito.ativo, isTrue);
      expect(StatusTurno.emAndamento.ativo, isTrue);
    });

    test('inativo para finalizado e cancelado', () {
      expect(StatusTurno.finalizado.ativo, isFalse);
      expect(StatusTurno.cancelado.ativo, isFalse);
    });
  });
}
