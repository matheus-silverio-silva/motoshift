// As regras do histórico moravam dentro do State da tela e só eram
// exercitadas por golden — e um golden que muda de cor não diz qual predicado
// quebrou. Extraídas para HistoricoResumo, dá para cobri-las direto.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/views/historico_turnos/historico_resumo.dart';

Turno _turno({
  required int id,
  required StatusTurno status,
  PagamentoStatus pagamento = PagamentoStatus.naoAplicavel,
  double valor = 100,
  Duration duracao = const Duration(hours: 4),
  bool lojistaConfirmou = false,
  bool motoboyConfirmou = false,
}) {
  final inicio = DateTime(2026, 8, 19, 8);
  return Turno(
    id: id,
    lojistId: 1,
    titulo: 'Turno $id',
    regiao: 'Centro',
    dataInicio: inicio,
    dataFim: inicio.add(duracao),
    valorEstimado: valor,
    raioEntregaKm: 5,
    status: status,
    pagamentoStatus: pagamento,
    lojistaConfirmouEm: lojistaConfirmou ? inicio : null,
    motoboyConfirmouEm: motoboyConfirmou ? inicio : null,
  );
}

HistoricoResumo _resumo(List<Turno> turnos, {Set<int> avaliados = const {}}) =>
    HistoricoResumo(turnos: turnos, avaliados: avaliados);

void main() {
  group('Contagem por estado', () {
    test('expirado não é contado como cancelado', () {
      final r = _resumo([
        _turno(id: 1, status: StatusTurno.cancelado),
        _turno(id: 2, status: StatusTurno.expirado),
        _turno(id: 3, status: StatusTurno.expirado),
      ]);

      // O defeito original: a tela só conhecia finalizado|cancelado, e o
      // expirado sumia — ou pior, era rotulado como outra coisa.
      expect(r.qtdCancelados, 1);
      expect(r.qtdExpirados, 2);
      expect(r.qtdFinalizados, 0);
    });

    test('a aba "expirados" isola só os expirados', () {
      final r = _resumo([
        _turno(id: 1, status: StatusTurno.finalizado),
        _turno(id: 2, status: StatusTurno.cancelado),
        _turno(id: 3, status: StatusTurno.expirado),
      ]);

      expect(r.filtrar('expirados').map((t) => t.id), [3]);
      expect(r.filtrar('cancelados').map((t) => t.id), [2]);
      expect(r.filtrar('todos').map((t) => t.id), [1, 2, 3]);
    });

    test('cancelado e expirado compartilham o tratamento "sem entrega"', () {
      final r = _resumo(const []);
      expect(r.semEntrega(_turno(id: 1, status: StatusTurno.cancelado)), isTrue);
      expect(r.semEntrega(_turno(id: 2, status: StatusTurno.expirado)), isTrue);
      expect(
          r.semEntrega(_turno(id: 3, status: StatusTurno.finalizado)), isFalse);
    });
  });

  group('Avaliação', () {
    test('turno já avaliado sai da fila', () {
      final turnos = [
        _turno(id: 1, status: StatusTurno.finalizado),
        _turno(id: 2, status: StatusTurno.finalizado),
      ];

      expect(_resumo(turnos).qtdAvaliar, 2);
      expect(_resumo(turnos, avaliados: {1}).qtdAvaliar, 1);
      expect(_resumo(turnos, avaliados: {1, 2}).qtdAvaliar, 0);
    });

    test('cancelado e expirado nunca entram na fila de avaliação', () {
      final r = _resumo([
        _turno(id: 1, status: StatusTurno.cancelado),
        _turno(id: 2, status: StatusTurno.expirado),
      ]);
      expect(r.qtdAvaliar, 0);
    });
  });

  group('Pagamento', () {
    test('só finalizado e pendente conta como aguardando', () {
      final r = _resumo([
        _turno(
            id: 1,
            status: StatusTurno.finalizado,
            pagamento: PagamentoStatus.pendente,
            valor: 120),
        _turno(
            id: 2,
            status: StatusTurno.finalizado,
            pagamento: PagamentoStatus.pago,
            valor: 100),
        // Cancelado com pagamento pendente não é dívida de ninguém.
        _turno(
            id: 3,
            status: StatusTurno.cancelado,
            pagamento: PagamentoStatus.pendente,
            valor: 999),
      ]);

      expect(r.qtdPagamento, 1);
      expect(r.valorPendente, 120);
      expect(r.totalGanho, 100);
    });

    test('quem já confirmou sai da lista de quem precisa confirmar', () {
      final pendente = _turno(
        id: 1,
        status: StatusTurno.finalizado,
        pagamento: PagamentoStatus.pendente,
      );
      final lojistaJa = _turno(
        id: 2,
        status: StatusTurno.finalizado,
        pagamento: PagamentoStatus.pendente,
        lojistaConfirmou: true,
      );
      final r = _resumo([pendente, lojistaJa]);

      expect(r.lojistaPrecisaConfirmar(pendente), isTrue);
      expect(r.lojistaPrecisaConfirmar(lojistaJa), isFalse);
      expect(r.motoboyPrecisaConfirmar(lojistaJa), isTrue);
    });
  });

  group('Métricas do desktop', () {
    test('o expirado entra no denominador da taxa de conclusão', () {
      // Turno que ninguém pegou é uma falha em preencher. Se o denominador
      // fosse só finalizado+cancelado, a taxa ignoraria isso e ficaria alta
      // justamente quando o lojista mais precisa notar.
      final comExpirado = _resumo([
        _turno(id: 1, status: StatusTurno.finalizado),
        _turno(id: 2, status: StatusTurno.expirado),
      ]);
      expect(comExpirado.percentualConclusao, 50);

      final semExpirado =
          _resumo([_turno(id: 1, status: StatusTurno.finalizado)]);
      expect(semExpirado.percentualConclusao, 100);
    });

    test('médias devolvem zero em vez de dividir por zero', () {
      final vazio = _resumo(const []);
      expect(vazio.percentualConclusao, 0);
      expect(vazio.mediaPorTurno, 0);
      expect(vazio.mediaHoras, 0);
      expect(vazio.maisAntigo, isNull);
    });

    test('horas rodadas somam só os finalizados', () {
      final r = _resumo([
        _turno(
            id: 1,
            status: StatusTurno.finalizado,
            duracao: const Duration(hours: 4)),
        _turno(
            id: 2,
            status: StatusTurno.finalizado,
            duracao: const Duration(hours: 2)),
        _turno(
            id: 3,
            status: StatusTurno.cancelado,
            duracao: const Duration(hours: 8)),
      ]);

      expect(r.horasRodadas, 6);
      expect(r.mediaHoras, 3);
    });
  });
}
