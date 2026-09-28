// Reputação e avaliação sem número de enfeite.
//
// O que estes testes prendem: conta nova não abre em "5.00 — Excelente" (é
// "Novo na plataforma"); o lojista não tem score em lugar nenhum; a estrela
// é sempre avaliação, nunca score; e quem avalia marca o que o OUTRO lado faz
// — o lojista avalia entregador por "Cuidado com a carga", o entregador avalia
// loja por "Pedidos prontos no horário".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/tags_de_avaliacao.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/dashboard_api.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/views/avaliacao/avaliacao_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/perfil_publico/perfil_publico_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  group('Score', () {
    test('sem score no JSON, o usuário não tem score — nada de 5,0 por omissão', () {
      final u = Usuario.fromJson({
        'id': 9,
        'nome': 'Entregador Novo',
        'email': 'novo@x.com',
        'telefone': '41999990000',
        'tipo': 'MOTOBOY',
      });
      expect(u.score, isNull);
      expect(u.mediaAvaliacao, isNull);
    });

    testWidgets('painel do entregador novo diz "Novo na plataforma", não "Excelente"',
        (tester) async {
      await pumpGolden(
        tester,
        usuario: _entregadorNovo(),
        apiFake: _ApiDeEntregadorNovo(),
        child: DashboardMotoboyScreen(agora: dataAncoraGolden),
      );

      expect(find.text('Novo na plataforma'), findsWidgets);
      expect(find.text('Excelente'), findsNothing);
      expect(find.text('5.00'), findsNothing);
    });

    testWidgets('perfil do lojista não mostra reputação', (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.lojista,
          child: PerfilScreen(agora: dataAncoraGolden));

      expect(find.textContaining('reputação'), findsNothing);
      expect(find.byKey(const Key('perfil-novo-na-plataforma')), findsNothing);
    });

    testWidgets('perfil do entregador novo diz que é novo', (tester) async {
      await pumpGolden(tester,
          usuario: _entregadorNovo(),
          child: PerfilScreen(agora: dataAncoraGolden));

      expect(find.byKey(const Key('perfil-novo-na-plataforma')), findsOneWidget);
      expect(find.textContaining('reputação'), findsNothing);
    });

    testWidgets('perfil público da loja: avaliação sim, reputação não', (tester) async {
      await pumpGolden(tester,
          child: const PerfilPublicoScreen(),
          argumentos: const PerfilPublicoArgs(usuarioId: 2));

      expect(find.text('Reputação'), findsNothing);
      // A avaliação continua no cabeçalho, com estrela.
      expect(find.textContaining('4,8'), findsOneWidget);
    });

    testWidgets('perfil público do entregador: reputação e avaliação, cada uma com o seu número',
        (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.lojista,
          child: const PerfilPublicoScreen(),
          argumentos: const PerfilPublicoArgs(usuarioId: 1));

      expect(find.text('Reputação'), findsOneWidget);
      expect(find.textContaining('4,7'), findsOneWidget);
      expect(find.textContaining('4,8'), findsOneWidget);
    });
  });

  group('Tags de avaliação', () {
    test('cada lista fala do que o avaliado faz', () {
      expect(TagsDeAvaliacao.para(TipoUsuario.motoboy),
          containsAll(['Pontual', 'Cuidado com a carga', 'Conhece a região']));
      expect(TagsDeAvaliacao.para(TipoUsuario.motoboy),
          isNot(contains('Carga bem embalada')));
      expect(TagsDeAvaliacao.para(TipoUsuario.lojista),
          containsAll(['Pedidos prontos no horário', 'Carga bem embalada', 'Endereços corretos']));
      expect(TagsDeAvaliacao.para(TipoUsuario.lojista), isNot(contains('Pontual')));
      // Com a liquidação automática a loja não tem como pagar errado.
      expect(TagsDeAvaliacao.para(TipoUsuario.lojista), isNot(contains('Pagamento correto')));
    });

    testWidgets('o lojista avaliando o entregador vê as tags do entregador',
        (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.lojista,
          child: const AvaliacaoScreen(),
          argumentos: const AvaliacaoArgs(
              turnoId: 1, avaliadorId: 2, avaliadoId: 1, nomeAvaliado: 'Ricardo Souza'));

      expect(find.text('Cuidado com a carga'), findsOneWidget);
      expect(find.text('Carga bem embalada'), findsNothing);
    });

    testWidgets('o entregador avaliando a loja vê as tags da loja', (tester) async {
      await pumpGolden(tester,
          tipoUsuario: TipoUsuario.motoboy,
          child: const AvaliacaoScreen(),
          argumentos: const AvaliacaoArgs(
              turnoId: 1, avaliadorId: 1, avaliadoId: 2, nomeAvaliado: 'Cláudia Oliveira'));

      expect(find.text('Pedidos prontos no horário'), findsOneWidget);
      expect(find.text('Pontual'), findsNothing);
    });
  });
}

Usuario _entregadorNovo() => Usuario(
      id: 7,
      nome: 'Pedro Novato',
      email: 'pedro@x.com',
      telefone: '41999990000',
      tipo: TipoUsuario.motoboy,
      criadoEm: DateTime(2026, 8, 18),
    );

class _ApiDeEntregadorNovo extends FakeApiService {
  @override
  DashboardApi get dashboard => _DashboardNovo();
}

class _DashboardNovo extends DashboardApi {
  _DashboardNovo() : super(ApiClient());

  @override
  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) async => {
        'score': null,
        'novoNaPlataforma': true,
        'saldoAtual': 0.0,
        'ganhosMensais': 0.0,
        'turnosFinalizadosMes': 0,
        'turnosFinalizados': 0,
        'mediaAvaliacao': null,
        'ganhosDiarios': <double>[],
      };
}
