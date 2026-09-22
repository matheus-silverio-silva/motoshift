// A pendência de avaliação num turno com mais de um entregador (C9).
//
// O defeito: `/avaliacoes/feitas/{id}` devolve ids DISTINTOS de turno, e as
// telas tratavam "o turno está nessa lista" como "o turno está avaliado".
// O lojista de um turno de três vagas avaliava o primeiro entregador e o
// turno inteiro sumia da fila — os outros dois ficavam sem nota e sem
// caminho até ela.
//
// O PendenciasProvider pergunta por turno em
// `/avaliacoes/turno/{id}/pendentes/{usuarioId}`, que sabe quantos faltam.
// Estes testes montam exatamente o cenário do defeito e conferem que a
// pendência sobrevive à primeira avaliação.

import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/presentation/providers/pendencias_provider.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/avaliacao_api.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/services/api_service.dart';

import '../test_helpers.dart';

const _turnoMultiVaga = 900;

/// Três entregadores no turno; [avaliados] diz quantos já receberam nota.
class _AvaliacoesMultiVaga extends AvaliacaoApi {
  _AvaliacoesMultiVaga() : super(ApiClient());

  final _entregadores = const [
    {'usuarioId': 11, 'nome': 'Lucas Mendes'},
    {'usuarioId': 12, 'nome': 'Thiago Alves'},
    {'usuarioId': 13, 'nome': 'Rafael Costa'},
  ];
  int avaliados = 0;

  /// O que a rota antiga responderia: basta UMA avaliação para o turno
  /// aparecer aqui. Se o provider ainda olhasse para isto, os testes abaixo
  /// quebrariam.
  @override
  Future<List<int>> buscarTurnosAvaliados(int usuarioId) async =>
      avaliados > 0 ? [_turnoMultiVaga] : [];

  @override
  Future<({bool precisaAvaliar, List<Map<String, dynamic>> pendentes})>
      buscarAvaliacoesPendentes(int turnoId, int usuarioId) async {
    final faltam = _entregadores.skip(avaliados).toList();
    return (precisaAvaliar: faltam.isNotEmpty, pendentes: faltam);
  }
}

class _TurnosMultiVaga extends FakeTurnoApi {
  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) async => [
        Turno(
          id: _turnoMultiVaga,
          lojistId: 2,
          motoboyId: 11,
          titulo: 'Sexta cheia — Rebouças',
          regiao: 'Rebouças, Curitiba',
          dataInicio: DateTime(2026, 9, 18, 17),
          dataFim: DateTime(2026, 9, 18, 22),
          valorEstimado: 150,
          raioEntregaKm: 6,
          vagas: 3,
          status: StatusTurno.finalizado,
        ),
      ];
}

class _Api extends FakeApiService {
  final avaliacoesFake = _AvaliacoesMultiVaga();
  final _turnos = _TurnosMultiVaga();

  @override
  AvaliacaoApi get avaliacoes => avaliacoesFake;

  @override
  TurnoApi get turnos => _turnos;
}

void main() {
  late _Api api;
  late PendenciasProvider pendencias;

  setUp(() {
    api = _Api();
    pendencias = PendenciasProvider(api as ApiService);
  });

  test('turno de três vagas conta três avaliações, não um turno', () async {
    await pendencias.carregar(fakeLojista());

    expect(pendencias.turnosAAvaliar, hasLength(1));
    expect(pendencias.quantidadeAvaliacoes, 3);
    expect(
      pendencias.avaliacoesDoTurno(_turnoMultiVaga).map((p) => p.nome),
      ['Lucas Mendes', 'Thiago Alves', 'Rafael Costa'],
    );
  });

  test('avaliar o primeiro entregador NÃO tira o turno da fila', () async {
    api.avaliacoesFake.avaliados = 1;
    await pendencias.carregar(fakeLojista());

    // É aqui que o código antigo errava: o turno já aparece em
    // /avaliacoes/feitas, e a fila ficava vazia.
    expect(await api.avaliacoes.buscarTurnosAvaliados(2), [_turnoMultiVaga]);
    expect(pendencias.turnosAAvaliar, hasLength(1));
    expect(pendencias.quantidadeAvaliacoes, 2);
    expect(
      pendencias.avaliacoesDoTurno(_turnoMultiVaga).map((p) => p.nome),
      ['Thiago Alves', 'Rafael Costa'],
    );
  });

  test('só depois do último o turno sai da fila', () async {
    api.avaliacoesFake.avaliados = 3;
    await pendencias.carregar(fakeLojista());

    expect(pendencias.turnosAAvaliar, isEmpty);
    expect(pendencias.quantidadeAvaliacoes, 0);
  });

  test('logout limpa a pendência da conta que saiu', () async {
    await pendencias.carregar(fakeLojista());
    expect(pendencias.quantidadeAvaliacoes, 3);

    pendencias.limpar();

    expect(pendencias.quantidadeAvaliacoes, 0);
    expect(pendencias.carregado, isFalse);
  });
}
