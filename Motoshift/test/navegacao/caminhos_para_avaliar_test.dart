// Os cinco caminhos até "avaliar", para os dois papéis, nas duas larguras.
//
// Avaliar é alcançável de cinco lugares, e antes desta versão cada um levava
// a um destino diferente: três passavam o título do turno como nome de quem
// era avaliado, o histórico mandava o lojista avaliar só o primeiro
// entregador de um turno multi-vaga, e o desktop não tinha "Avaliar" no
// histórico. Hoje os cinco passam por `abrirAvaliacao`, e este arquivo prende
// isso — 5 caminhos × 2 papéis × 2 larguras = 20 casos, todos exigindo:
//
//   * lojista  → /avaliar-entregadores, do turno certo (a tela lista cada
//                entregador pendente);
//   * entregador → /avaliacao, com o NOME DA LOJA, e não o título do turno;
//   * no desktop, a avaliação do entregador abre como modal sobre a tela de
//     origem (rota não opaca), e não no lugar dela.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/routes/nav_config.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/notificacao_api.dart';
import 'package:moto_shift/views/avaliacao/avaliacao_screen.dart';
import 'package:moto_shift/views/avaliar_entregadores/avaliar_entregadores_screen.dart';

import '../test_helpers.dart';
import 'app_de_teste.dart';

/// O turno finalizado de cada papel nos fakes — com avaliação pendente.
Turno _finalizado(TipoUsuario papel) => papel == TipoUsuario.lojista
    ? fakeTurnosLojista().firstWhere((t) => t.id == 303)
    : fakeMeusTurnos().firstWhere((t) => t.id == 202);

class _NotificacaoDeAvaliacao extends NotificacaoApi {
  _NotificacaoDeAvaliacao(this.turnoId) : super(ApiClient());
  final int turnoId;

  @override
  Future<List<Map<String, dynamic>>> listarNotificacoes(int usuarioId,
          {bool apenasNaoLidas = false}) async =>
      [
        {
          'id': 1,
          'tipo': 'avaliacao_pendente',
          'titulo': 'Turno finalizado',
          'mensagem': 'Avalie a outra parte.',
          'referenciaTipo': 'turno',
          'referenciaId': turnoId,
          'lida': false,
          'criadoEm': DateTime(2026, 9, 1, 10).toIso8601String(),
        },
      ];

  @override
  Future<int> contarNotificacoesNaoLidas(int usuarioId) async => 1;

  @override
  Future<void> marcarNotificacaoLida(int id) async {}
}

class _ApiComNotificacao extends FakeApiService {
  _ApiComNotificacao(int turnoId)
      : _notificacoes = _NotificacaoDeAvaliacao(turnoId);
  final NotificacaoApi _notificacoes;

  @override
  NotificacaoApi get notificacoes => _notificacoes;
}

/// Um caminho: onde começa e o que tocar até pedir a avaliação.
class _Caminho {
  const _Caminho(this.nome, this.percorrer);
  final String nome;
  final Future<AppDeTeste> Function(
      WidgetTester tester, TipoUsuario papel, Size largura) percorrer;
}

Finder _botaoAvaliar() => find.text('Avaliar').first;

final _caminhos = <_Caminho>[
  _Caminho('detalhe do turno', (tester, papel, largura) async {
    final turno = _finalizado(papel);
    final app = await montarApp(
      tester,
      papel: papel,
      largura: largura,
      rota: papel == TipoUsuario.lojista
          ? AppRoutes.turnoLojista
          : AppRoutes.detalheTurno,
      argumentos: turno,
    );
    await tocar(tester, find.byKey(const Key('acao-avaliar')));
    return app;
  }),
  _Caminho('notificação', (tester, papel, largura) async {
    final app = await montarApp(
      tester,
      papel: papel,
      largura: largura,
      rota: AppRoutes.notificacoes,
      api: _ApiComNotificacao(_finalizado(papel).id!),
    );
    await tocar(tester, find.text('Turno finalizado'));
    return app;
  }),
  _Caminho('painel de pendências do início', (tester, papel, largura) async {
    final app = await montarApp(
      tester,
      papel: papel,
      largura: largura,
      rota: NavConfig.raizDe(papel),
    );
    await tocar(tester, find.textContaining('a fazer'));
    expect(app.paginas.last, AppRoutes.minhasAvaliacoes,
        reason: 'o painel leva à central, onde está a lista');
    await tocar(tester, _botaoAvaliar());
    return app;
  }),
  _Caminho('central de Avaliações', (tester, papel, largura) async {
    final app = await montarApp(
      tester,
      papel: papel,
      largura: largura,
      rota: AppRoutes.minhasAvaliacoes,
    );
    await tocar(tester, _botaoAvaliar());
    return app;
  }),
  _Caminho('histórico', (tester, papel, largura) async {
    final app = await montarApp(
      tester,
      papel: papel,
      largura: largura,
      rota: AppRoutes.historicoTurnos,
    );
    await tocar(tester, _botaoAvaliar());
    return app;
  }),
];

void main() {
  setUpAll(setupGoldenTests);

  for (final caminho in _caminhos) {
    for (final papel in TipoUsuario.values) {
      for (final largura in [celular, desktop]) {
        testWidgets(
            '${caminho.nome} → avaliar (${papel.name}, '
            '${nomeDaLargura(largura)})', (tester) async {
          final app = await caminho.percorrer(tester, papel, largura);
          expect(tester.takeException(), isNull);

          if (papel == TipoUsuario.lojista) {
            expect(app.paginas.last, AppRoutes.avaliarEntregadores);
            final args = app.espiao
                .ultimaCom(AppRoutes.avaliarEntregadores)!
                .arguments as AvaliarEntregadoresArgs;
            expect(args.turnoId, isNotNull);
            return;
          }

          expect(app.paginas.last, AppRoutes.avaliacao);
          final args = app.espiao.ultimaCom(AppRoutes.avaliacao)!.arguments
              as AvaliacaoArgs;
          expect(args.nomeAvaliado, 'Hamburgueria da Cláudia',
              reason: 'o nome é o da loja avaliada, não o título do turno');
          expect(args.avaliadoId, 2);

          final rota = app.espiao.pilha.last as ModalRoute<dynamic>;
          if (largura == desktop) {
            expect(rota.opaque, isFalse,
                reason: 'no desktop a avaliação é modal sobre a tela de '
                    'origem, não uma página no lugar dela');
          } else {
            expect(rota.opaque, isTrue);
          }
        });
      }
    }
  }
}
