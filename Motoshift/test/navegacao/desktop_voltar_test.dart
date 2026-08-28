// A topbar do desktop não tinha botão de voltar.
//
// Sete telas usam `AppHeader.back(...)` no mobile e perdiam isso no desktop:
// agendar turno, avaliar entregadores, carteira, histórico, minhas avaliações,
// notificações e saldo do lojista. O lojista clicava no sino, ia para
// /notificacoes e não tinha como voltar — a única saída era a sidebar, que faz
// `pushReplacementNamed`. E /notificacoes não é item de sidebar, então nenhum
// item ficava destacado: a pessoa não sabia nem onde estava.
//
// A seta aparece por `Navigator.canPop()`, então estes testes cobrem os dois
// lados: tela empilhada ganha a seta e ela funciona; tela de raiz não ganha.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/notificacao_provider.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/presentation/providers/turno_selecionado_provider.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/theme/app_theme.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/notificacoes/notificacoes_screen.dart';
import 'package:moto_shift/widgets/desktop/app_topbar.dart';

import '../test_helpers.dart';

const _desktop = Size(1440, 1024);

final _seta = find.descendant(
  of: find.byType(AppTopbar),
  matching: find.byIcon(Icons.arrow_back_rounded),
);

/// Monta a tela EMPILHADA sobre uma raiz — é a situação real: o usuário chega
/// em /notificacoes por um `pushNamed` a partir do sino.
Future<void> _montarEmpilhada(
  WidgetTester tester, {
  required Widget tela,
  required TipoUsuario tipoUsuario,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _desktop;
  await tester.binding.setSurfaceSize(_desktop);

  final api = FakeApiService();
  final usuario =
      tipoUsuario == TipoUsuario.lojista ? fakeLojista() : fakeMotoboy();
  final auth = AuthService(api)..atualizarUsuarioLocal(usuario);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<TurnoProvider>(create: (_) => TurnoProvider(api)),
        ChangeNotifierProvider<TurnoSelecionadoProvider>(
          create: (_) => TurnoSelecionadoProvider(),
        ),
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
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => tela),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(setupGoldenTests);

  testWidgets('desktop: tela empilhada ganha a seta de voltar na topbar',
      (tester) async {
    await _montarEmpilhada(
      tester,
      tela: const NotificacoesScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );

    expect(find.byType(NotificacoesScreen), findsOneWidget);
    expect(_seta, findsOneWidget);
  });

  testWidgets('desktop: a seta volta de verdade — a tela sai da pilha',
      (tester) async {
    await _montarEmpilhada(
      tester,
      tela: const NotificacoesScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );

    await tester.tap(_seta);
    await tester.pumpAndSettle();

    expect(find.byType(NotificacoesScreen), findsNothing,
        reason: 'sem isto, /notificacoes é um beco sem saída no desktop');
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('desktop: tela de raiz não ganha seta', (tester) async {
    // O dashboard é alcançado por pushReplacement/pushNamedAndRemoveUntil:
    // não há para onde voltar, e uma seta ali seria mentira.
    await pumpGolden(
      tester,
      child: const DashboardMotoboyScreen(),
      viewport: _desktop,
    );

    expect(find.byType(AppTopbar), findsOneWidget);
    expect(_seta, findsNothing);
  });

  testWidgets('mobile: a topbar do desktop não entra em jogo', (tester) async {
    await pumpGolden(
      tester,
      child: const NotificacoesScreen(),
      tipoUsuario: TipoUsuario.lojista,
      viewport: const Size(390, 844),
    );

    // No celular quem dá o voltar continua sendo o AppHeader.back.
    expect(find.byType(AppTopbar), findsNothing);
  });
}
