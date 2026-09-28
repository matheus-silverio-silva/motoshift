import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/entregador_favorito.dart';
import 'package:moto_shift/models/notificacao.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/favoritos_provider.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/favorito_api.dart';
import 'package:moto_shift/views/avaliar_entregadores/avaliar_entregadores_screen.dart';
import 'package:moto_shift/views/meus_turnos/turnos_cards.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/perfil_publico/perfil_publico_screen.dart';
import 'package:moto_shift/views/turno_lojista/turno_lojista_screen.dart';

import '../test_helpers.dart';

/// Favoritos (V18): o coração é da loja, a lista mora no perfil dela, e o
/// entregador só vê o efeito — o selo "Loja que já te chamou".
void main() {
  setUpAll(setupGoldenTests);

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Turno turno({StatusTurno status = StatusTurno.finalizado, bool chamou = false}) =>
      Turno(
        id: 301,
        lojistId: 2,
        motoboyId: 1,
        titulo: 'Turno Noite — Hamburgueria',
        regiao: 'Água Verde, Curitiba',
        dataInicio: hojeAncorado().add(const Duration(days: 1, hours: 18)),
        dataFim: hojeAncorado().add(const Duration(days: 1, hours: 22)),
        valorEstimado: 130,
        raioEntregaKm: 8,
        status: status,
        lojaQueJaTeChamou: chamou,
      );

  group('perfil público do entregador', () {
    testWidgets('o lojista vê o coração; tocar tira dos favoritos e diz isso',
        (tester) async {
      final api = _ApiComFavoritos();
      await pumpGolden(tester,
          child: const PerfilPublicoScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: const PerfilPublicoArgs(usuarioId: 1, nome: 'Ricardo Souza'),
          apiFake: api);
      await esperar(tester);

      expect(find.byKey(const Key('favorito-1')), findsOneWidget);
      expect(find.text('Favorito'), findsOneWidget, reason: 'o Ricardo já é favorito');

      await tester.tap(find.byKey(const Key('favorito-1')));
      await esperar(tester);

      expect(find.text('Favoritar'), findsOneWidget);
      expect(api.fav.lista, isEmpty);
      expect(find.text('Ricardo saiu dos seus favoritos.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('favorito-1')));
      await esperar(tester);
      expect(find.text('Favorito'), findsOneWidget);
      expect(api.fav.lista.map((f) => f.motoboyId), [1]);
    });

    testWidgets('o entregador não tem coração', (tester) async {
      await pumpGolden(tester,
          child: const PerfilPublicoScreen(),
          tipoUsuario: TipoUsuario.motoboy,
          argumentos: const PerfilPublicoArgs(usuarioId: 1, nome: 'Ricardo Souza'));
      await esperar(tester);
      expect(find.byKey(const Key('favorito-1')), findsNothing);
    });

    testWidgets('erro do backend: o coração não muda e a mensagem aparece',
        (tester) async {
      final api = _ApiComFavoritos()..fav.falhar = true;
      await pumpGolden(tester,
          child: const PerfilPublicoScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: const PerfilPublicoArgs(usuarioId: 1, nome: 'Ricardo Souza'),
          apiFake: api);
      await esperar(tester);

      await tester.tap(find.byKey(const Key('favorito-1')));
      await esperar(tester);
      expect(find.text('Favorito'), findsOneWidget);
      expect(find.text('Sem conexao com o servidor'), findsOneWidget);
    });
  });

  group('perfil do lojista', () {
    testWidgets('lista "Meus entregadores favoritos"; o coração tira da lista',
        (tester) async {
      final api = _ApiComFavoritos();
      await pumpGolden(tester,
          child: const PerfilScreen(),
          tipoUsuario: TipoUsuario.lojista,
          apiFake: api);
      await esperar(tester);

      final secao = find.byKey(const Key('favoritos-do-lojista'));
      await tester.ensureVisible(secao);
      await tester.pump();
      expect(find.text('MEUS ENTREGADORES FAVORITOS'), findsOneWidget);
      expect(find.byKey(const Key('favorito-linha-1')), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('favorito-linha-1')),
          matching: find.byKey(const Key('favorito-1'))));
      await esperar(tester);
      expect(find.byKey(const Key('favorito-linha-1')), findsNothing);
      expect(find.byKey(const Key('favoritos-vazio')), findsOneWidget);
    });

    testWidgets('o entregador não tem a seção', (tester) async {
      await pumpGolden(tester,
          child: const PerfilScreen(), tipoUsuario: TipoUsuario.motoboy);
      await esperar(tester);
      expect(find.byKey(const Key('favoritos-do-lojista')), findsNothing);
    });
  });

  group('detalhe do turno do lojista', () {
    testWidgets('turno finalizado: coração no card do entregador', (tester) async {
      await pumpGolden(tester,
          child: const TurnoLojistScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: turno());
      await esperar(tester);
      await tester.scrollUntilVisible(find.text('Ver perfil'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.byKey(const Key('favorito-1')), findsOneWidget);
    });

    testWidgets('turno em curso: sem coração — ainda não se sabe como foi',
        (tester) async {
      await pumpGolden(tester,
          child: const TurnoLojistScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: turno(status: StatusTurno.aceito));
      await esperar(tester);
      await tester.scrollUntilVisible(find.text('Ver perfil'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.byKey(const Key('favorito-1')), findsNothing);
    });
  });

  testWidgets('avaliar entregadores: um coração por entregador', (tester) async {
    await pumpGolden(tester,
        child: const AvaliarEntregadoresScreen(),
        tipoUsuario: TipoUsuario.lojista,
        argumentos:
            const AvaliarEntregadoresArgs(turnoId: 501, tituloTurno: 'Turno Noite'));
    await esperar(tester);
    expect(find.byKey(const Key('favorito-1')), findsOneWidget);
  });

  group('selo "Loja que já te chamou"', () {
    test('vem do backend na lista de disponíveis', () {
      final json = {
        'id': 9,
        'lojistId': 2,
        'titulo': 'Turno',
        'regiao': 'Batel',
        'dataInicio': '2026-10-02T18:00:00',
        'dataFim': '2026-10-02T22:00:00',
        'valorEstimado': 130,
        'raioEntregaKm': 8,
        'status': 'aberto',
      };
      expect(Turno.fromJson(json).lojaQueJaTeChamou, isFalse);
      expect(Turno.fromJson({...json, 'lojaQueJaTeChamou': true}).lojaQueJaTeChamou,
          isTrue);
    });

    testWidgets('aparece só no turno da loja que favoritou', (tester) async {
      await pumpGolden(tester,
          child: Scaffold(
            body: Column(children: [
              TurnoDisponivelCard(
                  key: const Key('chamou'), turno: turno(status: StatusTurno.aberto, chamou: true)),
              TurnoDisponivelCard(
                  key: const Key('nao-chamou'), turno: turno(status: StatusTurno.aberto)),
            ]),
          ));
      expect(
          find.descendant(
              of: find.byKey(const Key('chamou')),
              matching: find.text('Loja que já te chamou')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('nao-chamou')),
              matching: find.text('Loja que já te chamou')),
          findsNothing);
    });
  });

  test('outra conta no mesmo aparelho não herda os corações', () async {
    final api = _ApiComFavoritos();
    final p = FavoritosProvider(api);
    await p.carregar(2);
    expect(p.ehFavorito(1), isTrue);

    api.fav.lista.clear();
    await p.carregar(3);
    expect(p.ehFavorito(1), isFalse, reason: 'a lista é da loja 3, não da 2');
  });

  test('a notificação de turno de favorito tem estilo próprio', () {
    final n = Notificacao.fromJson({
      'id': 1,
      'tipo': 'turno_de_favorito',
      'titulo': 'Turno novo de quem já te chamou',
      'mensagem': 'A Hamburgueria da Cláudia publicou um turno para amanhã, 18h.',
      'lida': false,
      'referenciaTipo': 'turno',
      'referenciaId': 9,
      'criadoEm': '2026-09-28T10:00:00',
    });
    expect(n.estilo.icone, Icons.favorite_rounded);
  });
}

class _FavoritosFalsos extends FakeFavoritoApi {
  bool falhar = false;

  @override
  Future<EntregadorFavorito> favoritar(int motoboyId) {
    if (falhar) throw const ApiException(0, 'Sem conexao com o servidor');
    return super.favoritar(motoboyId);
  }

  @override
  Future<void> desfavoritar(int motoboyId) {
    if (falhar) throw const ApiException(0, 'Sem conexao com o servidor');
    return super.desfavoritar(motoboyId);
  }
}

class _ApiComFavoritos extends FakeApiService {
  _ApiComFavoritos() : super(tipoUsuario: TipoUsuario.lojista);

  final _FavoritosFalsos fav = _FavoritosFalsos();

  @override
  FavoritoApi get favoritos => fav;
}
