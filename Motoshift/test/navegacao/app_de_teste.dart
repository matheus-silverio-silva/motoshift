// O app inteiro, com a tabela de rotas de verdade e a API falsa.
//
// Os testes de navegação não podem usar o `pumpGolden`: ele monta UMA tela e
// manda qualquer `pushNamed` para uma página em branco — ótimo para foto,
// inútil para saber aonde um botão leva. Aqui as rotas são as de
// `rotasDoApp()`, então tocar em "Avaliar" abre a tela de avaliação real, e o
// [EspiaoDeRotas] registra o caminho.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moto_shift/app.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/notificacao_provider.dart';
import 'package:moto_shift/presentation/providers/pendencias_provider.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/presentation/providers/turno_selecionado_provider.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/theme/app_theme.dart';

import '../test_helpers.dart';

const celular = Size(390, 844);
const desktop = Size(1280, 900);

String nomeDaLargura(Size s) => s.width < 1024 ? '390px' : '1280px';

/// Registra cada rota que entra na pilha — nome e argumentos — e mantém a
/// pilha atual, para os testes saberem se uma navegação empilhou ou trocou.
class EspiaoDeRotas extends NavigatorObserver {
  final entradas = <RouteSettings>[];
  final pilha = <Route<dynamic>>[];

  /// Nomes das rotas de página na pilha, de baixo para cima. Diálogos e
  /// menus suspensos ficam de fora: não são "onde a pessoa está".
  List<String?> get paginas => [
        for (final r in pilha)
          if (r is PageRoute) r.settings.name,
      ];

  List<String> get nomes => [
        for (final e in entradas)
          if (e.name != null) e.name!,
      ];

  RouteSettings? ultimaCom(String nome) {
    for (final e in entradas.reversed) {
      if (e.name == nome) return e;
    }
    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    entradas.add(route.settings);
    pilha.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pilha.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pilha.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) entradas.add(newRoute.settings);
    final i = oldRoute == null ? -1 : pilha.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      pilha[i] = newRoute;
    } else if (newRoute != null) {
      pilha.add(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class AppDeTeste {
  AppDeTeste(this.espiao, this.chave);

  final EspiaoDeRotas espiao;
  final GlobalKey<NavigatorState> chave;

  NavigatorState get navegador => chave.currentState!;

  List<String?> get paginas => espiao.paginas;
}

/// Monta o app começando em [rota], com a pilha contendo só ela.
///
/// `onGenerateInitialRoutes` em vez de `initialRoute`: com `initialRoute` o
/// Flutter empilha `/` antes da rota pedida, e toda tela começaria com uma
/// seta de voltar que o usuário de verdade não tem.
Future<AppDeTeste> montarApp(
  WidgetTester tester, {
  required TipoUsuario papel,
  required Size largura,
  required String rota,
  Object? argumentos,
  ApiService? api,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = largura;
  await tester.binding.setSurfaceSize(largura);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final servico = api ?? FakeApiService();
  final usuario =
      papel == TipoUsuario.lojista ? fakeLojista() : fakeMotoboy();
  final auth = AuthService(servico)..atualizarUsuarioLocal(usuario);
  final espiao = EspiaoDeRotas();
  final chave = GlobalKey<NavigatorState>();
  final rotas = rotasDoApp();

  await tester.runAsync(() async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: servico),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<TurnoProvider>(
              create: (_) => TurnoProvider(servico)),
          ChangeNotifierProvider<TurnoSelecionadoProvider>(
              create: (_) => TurnoSelecionadoProvider()),
          ChangeNotifierProvider<NotificacaoProvider>(
              create: (_) => NotificacaoProvider(servico)),
          ChangeNotifierProvider<PendenciasProvider>(
              create: (_) => PendenciasProvider(servico)),
        ],
        child: MaterialApp(
          navigatorKey: chave,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: rotas,
          navigatorObservers: [espiao],
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute(
              settings: RouteSettings(name: rota, arguments: argumentos),
              builder: rotas[rota]!,
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await assentar(tester);
  return AppDeTeste(espiao, chave);
}

/// Deixa terminar o que a tela disparou no primeiro quadro — carregamentos,
/// redirecionamentos do desktop, as pendências do menu.
///
/// Não é `pumpAndSettle` porque algumas telas têm animação contínua (o
/// indicador de carregamento do mapa), e aquilo nunca "assenta".
Future<void> assentar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Toca e espera a navegação terminar.
Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo, warnIfMissed: false);
  await assentar(tester);
}
