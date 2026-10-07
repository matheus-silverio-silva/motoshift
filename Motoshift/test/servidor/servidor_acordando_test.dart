import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/auth_api.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/services/servidor_service.dart';
import 'package:moto_shift/theme/app_theme.dart';
import 'package:moto_shift/views/login/login_screen.dart';
import 'package:moto_shift/views/splash/splash_screen.dart';
import 'package:moto_shift/widgets/auth_guard.dart';
import 'package:moto_shift/widgets/faixa_do_servidor.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// O servidor que demora a acordar (SCRUM-48).
///
/// No plano gratuito do Render o backend dorme depois de 15 minutos parado e
/// leva minutos para voltar; o app desiste de cada chamada em 20 segundos. O
/// primeiro login depois de um tempo parado falhava sempre. Agora o app
/// pergunta `/api/status` ao abrir e, se a resposta demora, avisa e espera.
///
/// Os tempos são os de produção (3 s, 5 s, 4 min): o relógio dos testes é
/// falso, e `pump(duração)` o adianta.
void main() {
  setUpAll(setupGoldenTests);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sessaoSalva = <String, Object>{'auth_token': 'token-salvo', 'user_id': 7};

  final faixaAcordando = find.byKey(const Key('servidor-acordando'));
  final faixaSemResposta = find.byKey(const Key('servidor-sem-resposta'));
  final tentarNovamente = find.byKey(const Key('servidor-tentar-novamente'));

  Finder campo(String chave) => find.descendant(
      of: find.byKey(Key(chave)), matching: find.byType(TextFormField));

  /// Deixa correr o que não depende do relógio (futuros já resolvidos).
  Future<void> assentarSemTempo(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  /// Monta [tela] como rota inicial; qualquer outra rota vira uma página com
  /// o nome dela, para o teste saber aonde a navegação foi.
  Future<AuthService> montar(
    WidgetTester tester, {
    required Widget tela,
    required FakeApiService api,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final auth = AuthService(api);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<AuthService>.value(value: auth),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: settings,
            builder: (_) => settings.name == '/'
                ? tela
                : Scaffold(body: Text('rota ${settings.name}')),
          ),
        ),
      ),
    );
    await assentarSemTempo(tester);
    return auth;
  }

  // ── A espera, sem tela ──────────────────────────────────────────────────

  group('ServidorService', () {
    testWidgets('servidor no ar: responde na hora e a faixa nunca aparece',
        (tester) async {
      final api = FakeApiService();
      final servidor = ServidorService(api);
      final estados = <EstadoDoServidor>[];
      servidor.addListener(() => estados.add(servidor.estado));

      expect(await servidor.aguardar(), isTrue);

      expect(estados, [EstadoDoServidor.noAr]);
      expect(api.statusFalso.perguntas, 1);
      servidor.dispose();
    });

    testWidgets(
        'servidor dormindo: avisa depois de 3 s, pergunta de novo a cada 5 s e para quando ele responde',
        (tester) async {
      final api = FakeApiService()..statusFalso.dormindo = true;
      final servidor = ServidorService(api);
      bool? resultado;
      servidor.aguardar().then((ok) => resultado = ok);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(servidor.estado, EstadoDoServidor.verificando,
          reason: 'antes dos 3 s ainda é uma resposta normal demorando');

      await tester.pump(const Duration(milliseconds: 200));
      expect(servidor.estado, EstadoDoServidor.acordando);
      expect(api.statusFalso.perguntas, 2);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(api.statusFalso.perguntas, 4);
      expect(resultado, isNull);

      api.statusFalso.acordar();
      await tester.pump();

      expect(servidor.estado, EstadoDoServidor.noAr);
      expect(resultado, isTrue);
      // Parou de perguntar: mais um minuto e a conta é a mesma.
      await tester.pump(const Duration(minutes: 1));
      expect(api.statusFalso.perguntas, 4);
      servidor.dispose();
    });

    testWidgets(
        'sem resposta em 4 minutos: desiste; tentar de novo recomeça a espera',
        (tester) async {
      final api = FakeApiService()..statusFalso.dormindo = true;
      final servidor = ServidorService(api);
      bool? resultado;
      servidor.aguardar().then((ok) => resultado = ok);

      await tester.pump(const Duration(minutes: 3, seconds: 55));
      expect(servidor.estado, EstadoDoServidor.acordando);
      expect(resultado, isNull);

      await tester.pump(const Duration(seconds: 10));
      expect(servidor.estado, EstadoDoServidor.semResposta);
      expect(resultado, isFalse);

      // "Tentar novamente": volta a perguntar, e desta vez ele responde.
      final perguntasAntes = api.statusFalso.perguntas;
      api.statusFalso.acordar();
      expect(await servidor.aguardar(), isTrue);
      expect(api.statusFalso.perguntas, perguntasAntes + 1);
      expect(servidor.estado, EstadoDoServidor.noAr);
      servidor.dispose();
    });

    testWidgets(
        'duas telas esperando ao mesmo tempo dividem a mesma espera, e resposta recente não é perguntada de novo',
        (tester) async {
      final api = FakeApiService()..statusFalso.dormindo = true;
      final servidor = ServidorService(api);

      final primeira = servidor.aguardar();
      final segunda = servidor.aguardar();
      expect(api.statusFalso.perguntas, 1);

      api.statusFalso.acordar();
      expect(await primeira, isTrue);
      expect(await segunda, isTrue);

      expect(await servidor.aguardar(), isTrue);
      expect(api.statusFalso.perguntas, 1);
      servidor.dispose();
    });

    testWidgets('descartado no meio da espera, não deixa timer para trás',
        (tester) async {
      final api = FakeApiService()..statusFalso.dormindo = true;
      final servidor = ServidorService(api);
      servidor.aguardar();
      await tester.pump(const Duration(seconds: 4));
      expect(servidor.estado, EstadoDoServidor.acordando);

      servidor.dispose();
      // Se sobrasse timer, o flutter_test reprovaria o teste ao terminar.
      await tester.pump(const Duration(minutes: 5));
    });
  });

  // ── O transporte ────────────────────────────────────────────────────────

  group('ApiClient', () {
    test('só uma resposta JSON abaixo de 500 prova que o backend acordou', () {
      expect(ApiClient.respostaDoBackend(200, 'application/json'), isTrue);
      expect(ApiClient.respostaDoBackend(200, 'application/json;charset=UTF-8'),
          isTrue);
      // Backend acordado, de uma versão sem a rota: 401 em JSON.
      expect(ApiClient.respostaDoBackend(401, 'application/json'), isTrue);
      // O proxy da hospedagem enquanto o serviço sobe.
      expect(ApiClient.respostaDoBackend(502, 'text/html'), isFalse);
      expect(ApiClient.respostaDoBackend(503, 'application/json'), isFalse);
      // Página de espera servida com 200.
      expect(ApiClient.respostaDoBackend(200, 'text/html; charset=utf-8'),
          isFalse);
      expect(ApiClient.respostaDoBackend(200, null), isFalse);
    });

    test('API_URL: com ou sem /api no fim, com ou sem barra, a base é a mesma',
        () {
      const esperado = 'https://motoshift.onrender.com/api';
      expect(ApiClient.baseDe('https://motoshift.onrender.com'), esperado);
      expect(ApiClient.baseDe('https://motoshift.onrender.com/'), esperado);
      expect(ApiClient.baseDe('https://motoshift.onrender.com/api'), esperado);
      expect(ApiClient.baseDe('https://motoshift.onrender.com/api/'), esperado);
      expect(ApiClient.baseDe(' https://motoshift.onrender.com/API '), esperado);
      expect(ApiClient.baseDe('http://localhost:8080'),
          'http://localhost:8080/api');
    });
  });

  // ── Login ───────────────────────────────────────────────────────────────

  group('login', () {
    testWidgets('servidor no ar: nenhuma faixa, e o botão é "Entrar"',
        (tester) async {
      final api = _ApiDeSessao();
      final auth = await montar(tester, tela: const LoginScreen(), api: api);

      expect(api.statusFalso.perguntas, 1, reason: 'a tela pergunta ao abrir');
      expect(faixaAcordando, findsNothing);
      expect(faixaSemResposta, findsNothing);
      expect(find.text('Entrar'), findsOneWidget);
      auth.dispose();
    });

    testWidgets(
        'servidor dormindo: a faixa aparece depois de 3 s e some quando o status responde',
        (tester) async {
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const LoginScreen(), api: api);

      await tester.pump(const Duration(seconds: 2));
      expect(faixaAcordando, findsNothing);
      expect(find.text('Entrar'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(faixaAcordando, findsOneWidget);
      expect(find.text(FaixaDoServidor.textoAcordando), findsOneWidget);
      expect(find.text('Aguardando o servidor'), findsOneWidget);
      expect(find.text('Entrar'), findsNothing);

      api.statusFalso.acordar();
      await tester.pump();

      expect(faixaAcordando, findsNothing);
      expect(find.text('Aguardando o servidor'), findsNothing);
      expect(find.text('Entrar'), findsOneWidget);
      auth.dispose();
    });

    testWidgets(
        'enquanto o servidor acorda, nem o botão nem o Enter chamam o login; depois, chamam',
        (tester) async {
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const LoginScreen(), api: api);
      await tester.enterText(campo('login-email'), 'claudia@teste.com');
      await tester.enterText(campo('login-senha'), 'senha123');
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Aguardando o servidor'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(api.authFalsa.logins, isEmpty);

      api.statusFalso.acordar();
      await tester.pump();
      await tester.tap(find.text('Entrar'));
      await tester.pump();

      expect(api.authFalsa.logins, [('claudia@teste.com', 'senha123')]);
      auth.dispose();
    });

    testWidgets(
        'o botão desligado diz ao leitor de tela o que está esperando, e a faixa é anunciada',
        (tester) async {
      final semantica = tester.ensureSemantics();
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const LoginScreen(), api: api);
      await tester.pump(const Duration(seconds: 4));

      final botao = tester.getSemantics(find.bySemanticsLabel(
          'Aguardando o servidor. O botão Entrar volta quando ele responder.'));
      final dados = botao.getSemanticsData();
      expect(dados.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(dados.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(dados.hasFlag(SemanticsFlag.isEnabled), isFalse);
      expect(dados.hasAction(SemanticsAction.tap), isFalse);

      final faixa = tester
          .getSemantics(find.bySemanticsLabel(FaixaDoServidor.textoAcordando));
      expect(faixa.getSemanticsData().hasFlag(SemanticsFlag.isLiveRegion),
          isTrue);

      auth.dispose();
      semantica.dispose();
    });

    testWidgets(
        'passados 4 minutos: erro com "Tentar novamente", e o botão volta para quem quiser tentar',
        (tester) async {
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const LoginScreen(), api: api);

      await tester.pump(const Duration(minutes: 4, seconds: 5));

      expect(faixaAcordando, findsNothing);
      expect(faixaSemResposta, findsOneWidget);
      expect(find.text(FaixaDoServidor.textoSemResposta), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);

      // Tentar de novo: a espera recomeça — sem faixa nos primeiros segundos,
      // com ela depois.
      await tester.tap(tentarNovamente);
      await tester.pump();
      expect(faixaSemResposta, findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(faixaAcordando, findsOneWidget);

      api.statusFalso.acordar();
      await tester.pump();
      expect(faixaAcordando, findsNothing);
      auth.dispose();
    });
  });

  // ── Sessão salva ────────────────────────────────────────────────────────

  group('sessão salva', () {
    testWidgets(
        'servidor dormindo: a abertura espera com a faixa, e entra quando ele acorda',
        (tester) async {
      SharedPreferences.setMockInitialValues(sessaoSalva);
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const SplashScreen(), api: api);

      await tester.pump(const Duration(seconds: 30));
      expect(faixaAcordando, findsOneWidget);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(api.authFalsa.buscas, 0,
          reason: 'não pergunta quem é o usuário a um servidor que não responde');

      api.statusFalso.acordar();
      await assentarSemTempo(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('rota ${AppRoutes.dashboardMotoboy}'), findsOneWidget);
      expect(auth.autenticado, isTrue);
      auth.dispose();
    });

    testWidgets(
        'sem resposta em 4 minutos: fica na abertura com o erro, a sessão continua salva e "Tentar novamente" entra',
        (tester) async {
      SharedPreferences.setMockInitialValues(sessaoSalva);
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const SplashScreen(), api: api);

      await tester.pump(const Duration(minutes: 4, seconds: 5));

      expect(faixaSemResposta, findsOneWidget);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(auth.inicializado, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-salvo');

      api.statusFalso.acordar();
      await tester.tap(tentarNovamente);
      await assentarSemTempo(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('rota ${AppRoutes.dashboardMotoboy}'), findsOneWidget);
      auth.dispose();
    });

    testWidgets('sem sessão salva: vai direto ao login, sem esperar o servidor',
        (tester) async {
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(tester, tela: const SplashScreen(), api: api);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('rota ${AppRoutes.login}'), findsOneWidget);
      expect(api.statusFalso.perguntas, 0);
      auth.dispose();
    });

    testWidgets(
        'recarregar a página numa tela interna: o guard espera o servidor e depois mostra a tela',
        (tester) async {
      SharedPreferences.setMockInitialValues(sessaoSalva);
      final api = _ApiDeSessao()..statusFalso.dormindo = true;
      final auth = await montar(
        tester,
        tela: const AuthGuard(child: Scaffold(body: Text('tela protegida'))),
        api: api,
      );

      await tester.pump(const Duration(seconds: 4));
      expect(faixaAcordando, findsOneWidget);
      expect(find.text('tela protegida'), findsNothing);

      api.statusFalso.acordar();
      await assentarSemTempo(tester);

      expect(find.text('tela protegida'), findsOneWidget);
      expect(faixaAcordando, findsNothing);
      auth.dispose();
    });

    testWidgets(
        'queda de rede ao restaurar não apaga a sessão salva; o servidor recusando o token, apaga',
        (tester) async {
      SharedPreferences.setMockInitialValues(sessaoSalva);
      final semRede = _ApiDeSessao()
        ..authFalsa.erroAoBuscar = const ApiException(0, 'Sem conexao com o servidor');
      final auth = AuthService(semRede);
      await auth.inicializar();

      expect(auth.inicializado, isTrue);
      expect(auth.autenticado, isFalse);
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-salvo');
      auth.dispose();

      final recusado = _ApiDeSessao()
        ..authFalsa.erroAoBuscar = const ApiException(401, 'Token expirado');
      final outra = AuthService(recusado);
      await outra.inicializar();

      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      outra.dispose();
    });
  });
}

/// Registra o que chegaria ao backend. O login é recusado — assim o teste não
/// precisa de navegação: o que interessa é se a chamada saiu.
class _AuthQueRegistra extends FakeAuthApi {
  final List<(String, String)> logins = [];
  int buscas = 0;
  ApiException? erroAoBuscar;

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String senha,
  }) async {
    logins.add((email, senha));
    throw const ApiException(401, 'Credenciais inválidas.');
  }

  @override
  Future<Usuario> buscarUsuario(int id) async {
    buscas++;
    final erro = erroAoBuscar;
    if (erro != null) throw erro;
    return fakeMotoboy();
  }
}

class _ApiDeSessao extends FakeApiService {
  final _AuthQueRegistra authFalsa = _AuthQueRegistra();

  @override
  AuthApi get auth => authFalsa;
}
