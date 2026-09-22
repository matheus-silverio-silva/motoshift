// Aonde cada notificação leva.
//
// Até esta versão, tocar numa notificação só a marcava como lida: ela
// carrega o id do turno, e as telas de detalhe recebem o objeto por
// argumento — não havia como montar o destino. O destino agora sai do
// `referenciaTipo`, e estes testes prendem a tabela inteira, para os dois
// papéis:
//
//   referenciaTipo   destino
//   turno            detalhe do turno (lojista: /turno-lojista)
//   turno + tipo     a própria avaliação daquele turno
//     avaliacao_pendente
//   carteira         a seção de dinheiro do papel (troca a pilha)
//   nota_fiscal      notas fiscais, abrindo aquela nota
//   outro            nada — só marca como lida
//
// e o caso de erro: turno que não existe mais não navega, e diz por quê.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Size;

import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/turno_selecionado_provider.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/notificacao_api.dart';
import 'package:moto_shift/views/notas_fiscais/notas_fiscais_screen.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';
import 'app_de_teste.dart';

/// Uma notificação só, com a referência pedida.
class _UmaNotificacao extends NotificacaoApi {
  _UmaNotificacao(this.dados) : super(ApiClient());
  final Map<String, dynamic> dados;

  @override
  Future<List<Map<String, dynamic>>> listarNotificacoes(int usuarioId,
          {bool apenasNaoLidas = false}) async =>
      [dados];

  @override
  Future<int> contarNotificacoesNaoLidas(int usuarioId) async => 1;

  @override
  Future<void> marcarNotificacaoLida(int id) async {}

  @override
  Future<int> marcarTodasNotificacoesLidas(int usuarioId) async => 0;
}

class _ApiComNotificacao extends FakeApiService {
  _ApiComNotificacao(Map<String, dynamic> dados)
      : _notificacoes = _UmaNotificacao(dados);
  final NotificacaoApi _notificacoes;

  @override
  NotificacaoApi get notificacoes => _notificacoes;
}

Map<String, dynamic> _notificacao({
  required String tipo,
  required String? referenciaTipo,
  required int? referenciaId,
}) =>
    {
      'id': 1,
      'tipo': tipo,
      'titulo': 'Toque aqui',
      'mensagem': 'Notificação de teste.',
      'referenciaTipo': referenciaTipo,
      'referenciaId': referenciaId,
      'lida': false,
      'criadoEm': DateTime(2026, 9, 1, 10).toIso8601String(),
    };

/// Turno aberto de cada papel e turno finalizado de cada papel, nos fakes.
int _turnoEmCurso(TipoUsuario p) => p == TipoUsuario.lojista ? 301 : 201;
int _turnoFinalizado(TipoUsuario p) => p == TipoUsuario.lojista ? 303 : 202;

Future<AppDeTeste> _tocarNaNotificacao(
  WidgetTester tester, {
  required TipoUsuario papel,
  required Map<String, dynamic> notificacao,
  Size largura = celular,
}) async {
  final app = await montarApp(
    tester,
    papel: papel,
    largura: largura,
    rota: AppRoutes.notificacoes,
    api: _ApiComNotificacao(notificacao),
  );
  await tocar(tester, find.text('Toque aqui'));
  return app;
}

void main() {
  setUpAll(setupGoldenTests);

  for (final papel in TipoUsuario.values) {
    final ehLojista = papel == TipoUsuario.lojista;

    group('${papel.name}:', () {
      testWidgets('turno abre o detalhe daquele turno', (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          notificacao: _notificacao(
            tipo: 'turno_aceito',
            referenciaTipo: 'turno',
            referenciaId: _turnoEmCurso(papel),
          ),
        );
        final destino =
            ehLojista ? AppRoutes.turnoLojista : AppRoutes.detalheTurno;
        expect(app.paginas, [AppRoutes.notificacoes, destino],
            reason: 'detalhe é sub-página: empilha, e voltar devolve às '
                'notificações');
        final turno = app.espiao.ultimaCom(destino)!.arguments as Turno;
        expect(turno.id, _turnoEmCurso(papel));
      });

      testWidgets('turno no desktop cai na lista com ele selecionado',
          (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          largura: desktop,
          notificacao: _notificacao(
            tipo: 'turno_aceito',
            referenciaTipo: 'turno',
            referenciaId: _turnoEmCurso(papel),
          ),
        );
        final lista = ehLojista
            ? AppRoutes.turnosLojista
            : AppRoutes.turnosDisponiveis;
        expect(app.paginas.last, lista);
        expect(
          Provider.of<TurnoSelecionadoProvider>(app.chave.currentContext!,
                  listen: false)
              .id,
          _turnoEmCurso(papel),
        );
      });

      testWidgets('avaliação pendente abre a avaliação daquele turno',
          (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          notificacao: _notificacao(
            tipo: 'avaliacao_pendente',
            referenciaTipo: 'turno',
            referenciaId: _turnoFinalizado(papel),
          ),
        );
        expect(
          app.paginas.last,
          ehLojista ? AppRoutes.avaliarEntregadores : AppRoutes.avaliacao,
        );
      });

      testWidgets('carteira troca a seção para o dinheiro do papel',
          (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          notificacao: _notificacao(
            tipo: 'pagamento_confirmado',
            referenciaTipo: 'carteira',
            referenciaId: _turnoFinalizado(papel),
          ),
        );
        expect(app.paginas,
            [ehLojista ? AppRoutes.saldoLojista : AppRoutes.carteira],
            reason: 'Saldo e Carteira são itens de menu: troca de seção, '
                'pilha nova');
      });

      testWidgets('nota fiscal abre as notas pedindo aquela nota',
          (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          notificacao: _notificacao(
            tipo: 'nota_emitida',
            referenciaTipo: 'nota_fiscal',
            referenciaId: 77,
          ),
        );
        expect(app.paginas.last, AppRoutes.notasFiscais);
        final args = app.espiao.ultimaCom(AppRoutes.notasFiscais)!.arguments;
        expect(args, isA<NotasFiscaisArgs>());
        expect((args as NotasFiscaisArgs).notaId, 77);
      });

      testWidgets('tipo desconhecido não inventa destino', (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          notificacao: _notificacao(
            tipo: 'coisa_nova',
            referenciaTipo: 'coisa_nova',
            referenciaId: 5,
          ),
        );
        expect(app.paginas, [AppRoutes.notificacoes]);
      });

      testWidgets('turno que não existe mais avisa e fica onde está',
          (tester) async {
        final app = await _tocarNaNotificacao(
          tester,
          papel: papel,
          notificacao: _notificacao(
            tipo: 'turno_aceito',
            referenciaTipo: 'turno',
            referenciaId: 999999,
          ),
        );
        expect(app.paginas, [AppRoutes.notificacoes]);
        expect(find.text('Não foi possível abrir este turno.'), findsOneWidget);
      });
    });
  }
}
