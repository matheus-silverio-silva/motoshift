// Fase 2 — o master-detail muda a NAVEGAÇÃO, não só o layout.
//
// O que estes testes protegem, e que nenhuma captura de tela mostra:
//   - no mobile, tocar num card empilha /detalhe-turno (comportamento atual);
//   - no desktop, tocar num card NÃO navega: só troca a seleção, e o painel
//     direito reage;
//   - abrir /detalhe-turno direto numa tela larga redireciona para a lista
//     com aquele turno já selecionado.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/presentation/providers/notificacao_provider.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/presentation/providers/turno_selecionado_provider.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/theme/app_theme.dart';
import 'package:moto_shift/views/detalhe_turno/detalhe_turno_screen.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/widgets/desktop/shift_row.dart';
import 'package:moto_shift/widgets/shift_card.dart';

import '../test_helpers.dart';

/// Registra as rotas empilhadas durante o teste.
class _Espiao extends NavigatorObserver {
  final rotas = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) {
    final nome = route.settings.name;
    if (nome != null) rotas.add(nome);
    super.didPush(route, previous);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final nome = newRoute?.settings.name;
    if (nome != null) rotas.add(nome);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

Future<TurnoSelecionadoProvider> _montar(
  WidgetTester tester, {
  required Widget tela,
  required Size viewport,
  required _Espiao espiao,
  Object? argumentos,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewport;
  await tester.binding.setSurfaceSize(viewport);

  final api = FakeApiService();
  final auth = AuthService(api)..atualizarUsuarioLocal(fakeMotoboy());
  final turnos = TurnoProvider(api)
    ..setDisponiveisExterno(fakeTurnosDisponiveis());
  final selecao = TurnoSelecionadoProvider();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<TurnoProvider>.value(value: turnos),
        ChangeNotifierProvider<TurnoSelecionadoProvider>.value(value: selecao),
        ChangeNotifierProvider<NotificacaoProvider>(
          create: (_) => NotificacaoProvider(api),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorObservers: [espiao],
        initialRoute: '/',
        onGenerateRoute: (settings) {
          if (settings.name == '/') {
            return MaterialPageRoute(
              settings: RouteSettings(name: '/', arguments: argumentos),
              builder: (_) => tela,
            );
          }
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  return selecao;
}

Turno _turnoDisponivel() => fakeTurnosDisponiveis().first;

void main() {
  setUpAll(setupGoldenTests);

  testWidgets('desktop: tocar num card seleciona sem empilhar rota',
      (tester) async {
    final espiao = _Espiao();
    final selecao = await _montar(
      tester,
      tela: const MeusTurnosScreen(),
      viewport: const Size(1440, 1024),
      espiao: espiao,
    );

    expect(selecao.id, isNull, reason: 'começa sem seleção');
    expect(find.text('Selecione um turno'), findsOneWidget);

    // Pelo conteúdo da linha, não pela posição: a lista da esquerda passou a
    // ter também a seção dos turnos aceitos, e a primeira linha nem sempre é
    // um turno disponível.
    await tester.tap(find.ancestor(
      of: find.textContaining(_turnoDisponivel().titulo),
      matching: find.byType(ShiftRow),
    ));
    await tester.pumpAndSettle();

    expect(selecao.id, _turnoDisponivel().id);
    expect(espiao.rotas, isNot(contains(AppRoutes.detalheTurno)),
        reason: 'no desktop o detalhe não é uma rota empilhada');
    // O painel direito reagiu: o cabeçalho do detalhe traz o título do turno.
    expect(find.text(_turnoDisponivel().titulo), findsWidgets);
    expect(find.text('Selecione um turno'), findsNothing);
  });

  testWidgets('mobile: tocar num card empilha /detalhe-turno', (tester) async {
    final espiao = _Espiao();
    final selecao = await _montar(
      tester,
      tela: const MeusTurnosScreen(),
      viewport: const Size(390, 844),
      espiao: espiao,
    );

    // Por widget, não por texto: o refinamento da Fase 5 juntou título e
    // região numa linha só, então o título deixou de ser um Text isolado.
    await tester.tap(find.byType(ShiftCard).first);
    await tester.pumpAndSettle();

    expect(espiao.rotas, contains(AppRoutes.detalheTurno));
    expect(selecao.id, isNull,
        reason: 'a seleção do master-detail não é usada no mobile');
  });

  testWidgets('desktop: /detalhe-turno redireciona para a lista já selecionada',
      (tester) async {
    final espiao = _Espiao();
    final turno = _turnoDisponivel();
    final selecao = await _montar(
      tester,
      tela: const DetalheTurnoScreen(),
      viewport: const Size(1440, 1024),
      espiao: espiao,
      argumentos: turno,
    );

    expect(espiao.rotas, contains(AppRoutes.turnosDisponiveis));
    expect(selecao.id, turno.id);
    expect(find.byType(DetalheTurnoScreen), findsNothing);
  });

  // ── Turno já aceito no desktop ─────────────────────────────────────────────
  //
  // `turnosDisponiveis` perde o turno no instante em que ele é aceito
  // (turno_provider.dart). Como o master-detail resolvia a seleção só contra
  // essa lista, o motoboy que clicasse no turno em andamento (dashboard ou
  // histórico do desktop) caía em "Turnos disponíveis" com o painel dizendo
  // "Selecione um turno" — o detalhe do turno que ele está rodando não tinha
  // como ser aberto no desktop. No mobile sempre funcionou.

  testWidgets('desktop: o turno já aceito aparece na lista da esquerda',
      (tester) async {
    final espiao = _Espiao();
    await _montar(
      tester,
      tela: const MeusTurnosScreen(),
      viewport: const Size(1440, 1024),
      espiao: espiao,
    );

    expect(find.text('MEUS TURNOS'), findsOneWidget,
        reason: 'a lista do desktop precisa da seção dos turnos aceitos');
    expect(find.textContaining('Turno Ativo — Hamburgueria'), findsWidgets);
  });

  testWidgets('desktop: selecionar um turno aceito abre o painel de detalhe',
      (tester) async {
    final espiao = _Espiao();
    final selecao = await _montar(
      tester,
      tela: const MeusTurnosScreen(),
      viewport: const Size(1440, 1024),
      espiao: espiao,
    );

    // 201 é o turno em andamento de fakeMeusTurnos(): está em `meusTurnos`,
    // nunca em `turnosDisponiveis`. É exatamente o id com que /detalhe-turno
    // redireciona para cá vindo do dashboard.
    selecao.selecionar(201);
    await tester.pumpAndSettle();

    expect(find.text('Selecione um turno'), findsNothing,
        reason: 'o painel não pode ficar vazio para um turno que existe');
    expect(find.text('Turno Ativo — Hamburgueria'), findsWidgets);
  });

  testWidgets('mobile: /detalhe-turno continua sendo a tela empilhada',
      (tester) async {
    final espiao = _Espiao();
    final turno = _turnoDisponivel();
    await _montar(
      tester,
      tela: const DetalheTurnoScreen(),
      viewport: const Size(390, 844),
      espiao: espiao,
      argumentos: turno,
    );

    expect(find.byType(DetalheTurnoScreen), findsOneWidget);
    expect(espiao.rotas, isNot(contains(AppRoutes.turnosDisponiveis)));
    expect(find.text('Detalhes do Turno'), findsOneWidget);
  });
}
