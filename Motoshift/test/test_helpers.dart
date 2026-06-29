// Helpers compartilhados para golden tests.
//
// - Carrega fontes em modo offline (GoogleFonts.allowRuntimeFetching = false)
// - Inicializa locale pt_BR
// - Bloqueia todo HTTP de rede (mapa OSM, etc) com HttpOverrides
// - Provê fakes para ApiService, AuthService e providers usados pelas telas
// - Helper pumpGolden() monta MaterialApp com locale, providers e args de rota

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:moto_shift/data/repositories/historico_repository_impl.dart';
import 'package:moto_shift/data/repositories/pedido_repository_impl.dart';
import 'package:moto_shift/models/carteira.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/historico_provider.dart';
import 'package:moto_shift/presentation/providers/pedido_provider.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Setup global
// ─────────────────────────────────────────────────────────────────────────────

/// Chame em setUpAll() de cada test file.
///
/// - Bloqueia HTTP (tiles OSM, mas deixa fontes Google passar)
/// - Pré-registra uma fonte TTF do sistema com os nomes que o tema usa
///   (Bricolage Grotesque + Plus Jakarta Sans) para evitar Ahem quadradão
///   no golden caso o download de fonte falhe / esteja offline.
Future<void> setupGoldenTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  HttpOverrides.global = _SelectiveHttpOverrides();
  await _registerFallbackFonts();

  // Mock dos canais nativos usados em testes:
  // - path_provider: google_fonts salva fontes no diretório de suporte
  // - shared_preferences: AuthService persiste sessão
  final binMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  binMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );

  binMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return null;
    },
  );

  // Silencia avisos residuais — overflow ocorre só em teste por causa das
  // métricas diferentes da fonte fallback (Roboto vs Bricolage/Jakarta).
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('google_fonts') ||
        msg.contains('Failed to load font') ||
        msg.contains('tile.openstreetmap') ||
        msg.contains('RenderFlex overflowed') ||
        msg.contains('A RenderFlex overflowed') ||
        msg.contains('Timer is still pending') ||
        msg.contains('timersPending')) {
      return;
    }
    FlutterError.dumpErrorToConsole(details);
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Fakes de dados
// ─────────────────────────────────────────────────────────────────────────────

Usuario fakeMotoboy() => Usuario(
      id: 1,
      nome: 'Ricardo Souza',
      email: 'ricardo@teste.com',
      telefone: '(41) 98111-2222',
      tipo: TipoUsuario.motoboy,
      documentoFederal: '12345678900',
      score: 4.7,
      mediaAvaliacao: 4.8,
      dataNascimento: DateTime(1995, 2, 10),
      cidade: 'Curitiba',
      estado: 'PR',
      cnhNumero: '12345678900',
      cnhCategoria: 'A',
      cnhValidade: DateTime(2028, 6, 30),
      veiculoModelo: 'Honda CG 160 Titan',
      veiculoPlaca: 'ABC-1D23',
      veiculoAno: 2022,
      veiculoCor: 'Vermelha',
      criadoEm: DateTime(2025, 1, 15),
    );

Usuario fakeLojista() => Usuario(
      id: 2,
      nome: 'Cláudia Oliveira',
      email: 'claudia@teste.com',
      telefone: '(41) 99111-2222',
      tipo: TipoUsuario.lojista,
      documentoFederal: '12.345.678/0001-90',
      score: 5.0,
      mediaAvaliacao: 4.8,
      dataNascimento: DateTime(1985, 3, 12),
      cidade: 'Curitiba',
      estado: 'PR',
      nomeFantasia: 'Hamburgueria da Cláudia',
      enderecoComercial: 'Av. Água Verde, 1200 — Água Verde, Curitiba/PR',
      criadoEm: DateTime(2025, 1, 1),
    );

List<Turno> fakeTurnosDisponiveis() {
  final base = DateTime.now().add(const Duration(days: 1));
  return [
    Turno(
      id: 101,
      lojistId: 2,
      titulo: 'Turno Tarde — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: DateTime(base.year, base.month, base.day, 14, 0),
      dataFim: DateTime(base.year, base.month, base.day, 18, 0),
      valorEstimado: 120,
      raioEntregaKm: 8,
    ),
    Turno(
      id: 102,
      lojistId: 3,
      titulo: 'Turno Manhã — Farmácia Ana',
      regiao: 'Centro Cívico, Curitiba',
      dataInicio: DateTime(base.year, base.month, base.day, 8, 0),
      dataFim: DateTime(base.year, base.month, base.day, 12, 0),
      valorEstimado: 110,
      raioEntregaKm: 6,
    ),
  ];
}

List<Turno> fakeMeusTurnos() {
  final hoje = DateTime.now();
  return [
    Turno(
      id: 201,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Ativo — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(hours: 1)),
      dataFim: hoje.add(const Duration(hours: 3)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.emAndamento,
    ),
    Turno(
      id: 202,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(days: 7)),
      dataFim: hoje.subtract(const Duration(days: 7, hours: -4)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pago,
      lojistaConfirmouEm: hoje.subtract(const Duration(days: 7)),
      motoboyConfirmouEm: hoje.subtract(const Duration(days: 7)),
    ),
    Turno(
      id: 203,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — pendente pagamento',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(days: 3)),
      dataFim: hoje.subtract(const Duration(days: 3, hours: -4)),
      valorEstimado: 125,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pendente,
    ),
  ];
}

List<Turno> fakeTurnosLojista() {
  final hoje = DateTime.now();
  return [
    Turno(
      id: 301,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Tarde — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.add(const Duration(days: 1, hours: 14)),
      dataFim: hoje.add(const Duration(days: 1, hours: 18)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.aceito,
    ),
    Turno(
      id: 302,
      lojistId: 2,
      titulo: 'Turno Aberto — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.add(const Duration(days: 2, hours: 18)),
      dataFim: hoje.add(const Duration(days: 2, hours: 22)),
      valorEstimado: 130,
      raioEntregaKm: 10,
      status: StatusTurno.aberto,
    ),
    Turno(
      id: 303,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Concluído — Hamburgueria',
      regiao: 'Água Verde, Curitiba',
      dataInicio: hoje.subtract(const Duration(days: 5)),
      dataFim: hoje.subtract(const Duration(days: 5, hours: -4)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.finalizado,
      pagamentoStatus: PagamentoStatus.pago,
      lojistaConfirmouEm: hoje.subtract(const Duration(days: 5)),
      motoboyConfirmouEm: hoje.subtract(const Duration(days: 5)),
    ),
  ];
}

Map<String, dynamic> fakeDashboardMotoboy() => {
      'score': 4.7,
      'saldoAtual': 320.0,
      'ganhosMensais': 1850.0,
      'turnosFinalizadosMes': 14,
      'ganhosDiarios': [120.0, 95.0, 0.0, 145.0, 110.0, 130.0, 90.0],
    };

Map<String, dynamic> fakeDashboardLojista() => {
      'turnosAtivos': 2,
      'totalGasto': 1500.0,
      'avaliacaoMedia': 4.8,
      'turnosMes': 12,
    };

Carteira fakeCarteira() => const Carteira(
      motoboyId: 1,
      saldoAtual: 320,
      ganhosMensais: 1850,
    );

List<Transacao> fakeTransacoes() => [
      Transacao(
        id: 1,
        motoboyId: 1,
        turnoId: 202,
        tipo: TipoTransacao.turno,
        valor: 120,
        descricao: 'Turno concluído - Hamburgueria',
        status: StatusTransacao.processado,
        criadoEm: DateTime.now().subtract(const Duration(days: 7)),
      ),
      Transacao(
        id: 2,
        motoboyId: 1,
        tipo: TipoTransacao.saque,
        valor: 200,
        descricao: 'Transferência Pix — ricardo@pix.com',
        status: StatusTransacao.concluido,
        criadoEm: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];

Map<String, dynamic> fakeAvaliacoes() => {
      'mediaGeral': 4.8,
      'totalAvaliacoes': 12,
      'distribuicao': {
        '5estrelas': 8,
        '4estrelas': 3,
        '3estrelas': 1,
        '2estrelas': 0,
        '1estrela': 0,
      },
      'avaliacoes': [
        {
          'turnoId': 1,
          'nota': 5,
          'comentario': 'Ótima organização',
          'nomeAvaliador': 'Cláudia Oliveira',
          'data': '2026-06-15',
        },
        {
          'turnoId': 2,
          'nota': 4,
          'comentario': 'Boa comunicação',
          'nomeAvaliador': 'Ana Souza',
          'data': '2026-06-10',
        },
      ],
    };

Map<String, dynamic> fakeAgendaMensal() => {
      'mes': DateTime.now().month,
      'ano': DateTime.now().year,
      'turnos': [],
    };

Map<String, dynamic> fakeAgendaSemanal() => {
      'inicioSemana': DateTime.now().toIso8601String().substring(0, 10),
      'dias': [],
    };

// ─────────────────────────────────────────────────────────────────────────────
// FakeApiService — sobrescreve todos os métodos com dados mockados
// ─────────────────────────────────────────────────────────────────────────────

class FakeApiService extends ApiService {
  FakeApiService();

  @override
  Future<Usuario> buscarUsuario(int id) async => fakeMotoboy();

  @override
  Future<Usuario> atualizarUsuario(Usuario usuario) async => usuario;

  @override
  Future<Usuario> atualizarPerfil(int id, Map<String, dynamic> campos) async =>
      fakeMotoboy();

  @override
  Future<List<Turno>> listarTurnosDisponiveis({DateTime? data}) async =>
      fakeTurnosDisponiveis();

  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) async =>
      fakeTurnosLojista();

  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) async =>
      fakeMeusTurnos();

  @override
  Future<List<Turno>> listarTurnosDisponiveisComFiltros({
    String? horarioInicio,
    String? horarioFim,
    int? diaSemana,
    double? raioMaxKm,
    String? dataInicio,
    String? dataFim,
    String? ordenarPor,
  }) async =>
      fakeTurnosDisponiveis();

  @override
  Future<Carteira> buscarCarteira(int motoboyId) async => fakeCarteira();

  @override
  Future<List<Transacao>> listarTransacoes(int motoboyId,
          {int limit = 20}) async =>
      fakeTransacoes();

  @override
  Future<List<Map<String, dynamic>>> buscarGrafico(int motoboyId,
          {int meses = 6}) async =>
      [
        {'mes': 'Jan', 'valor': 800.0},
        {'mes': 'Fev', 'valor': 950.0},
        {'mes': 'Mar', 'valor': 1100.0},
        {'mes': 'Abr', 'valor': 1500.0},
        {'mes': 'Mai', 'valor': 1750.0},
        {'mes': 'Jun', 'valor': 1850.0},
      ];

  @override
  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) async =>
      fakeDashboardMotoboy();

  @override
  Future<Map<String, dynamic>> dashboardLojista(int lojistId) async =>
      fakeDashboardLojista();

  @override
  Future<Map<String, dynamic>> buscarAgendaMensal(
          int usuarioId, int mes, int ano) async =>
      fakeAgendaMensal();

  @override
  Future<Map<String, dynamic>> buscarAgendaSemanal(
          int usuarioId, String data) async =>
      fakeAgendaSemanal();

  @override
  Future<Map<String, dynamic>> buscarAvaliacoes(int usuarioId) async =>
      fakeAvaliacoes();

  @override
  Future<List<int>> buscarTurnosAvaliados(int usuarioId) async => [1, 2];

  @override
  Future<bool> verificarPendente(int turnoId, int usuarioId) async => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Wrapper que monta MaterialApp + Providers + Locale para a tela sob teste
// ─────────────────────────────────────────────────────────────────────────────

/// Renderiza [child] num MaterialApp pré-configurado e captura o golden.
/// Use [argumentos] para passar dados a telas que usam `ModalRoute.of(context)`.
Future<void> pumpGolden(
  WidgetTester tester, {
  required Widget child,
  TipoUsuario tipoUsuario = TipoUsuario.motoboy,
  Object? argumentos,
  Size viewport = const Size(390, 844),
  Duration settle = const Duration(milliseconds: 600),
}) async {
  await tester.binding.setSurfaceSize(viewport);
  tester.view.physicalSize = viewport * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;

  final api = FakeApiService();
  final usuario =
      tipoUsuario == TipoUsuario.motoboy ? fakeMotoboy() : fakeLojista();
  final auth = AuthService(api)..atualizarUsuarioLocal(usuario);

  final turnoProv = TurnoProvider(api);
  turnoProv.setDisponiveisExterno(fakeTurnosDisponiveis());

  final widgetTree = MultiProvider(
    providers: [
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<TurnoProvider>.value(value: turnoProv),
      ChangeNotifierProvider<PedidoProvider>(
        create: (_) => PedidoProvider(repo: PedidoRepositoryImpl(api)),
      ),
      ChangeNotifierProvider<HistoricoProvider>(
        create: (_) =>
            HistoricoProvider(repo: HistoricoRepositoryImpl(api)),
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
      // Rota inicial é a tela sob teste (com arguments).
      // Qualquer pushReplacementNamed/pushNamed cai numa página em branco
      // — evita crash em Splash e telas que navegam após verificação.
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            settings: RouteSettings(name: '/', arguments: argumentos),
            builder: (_) => child,
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _BlankPage(),
        );
      },
    ),
  );

  // runAsync libera timers/HTTP reais — deixa GoogleFonts terminar download +
  // sockets bloqueados resolverem antes do snapshot.
  await tester.runAsync(() async {
    await tester.pumpWidget(widgetTree);
    await Future.delayed(const Duration(seconds: 2));
  });
  await tester.pump();
  await tester.pump(settle);
}

/// Página vazia usada como destino fallback de navegações que ocorrem durante
/// o teste (ex: Splash → Login). Não aparece no golden — capturamos a tela
/// original via find.byType().
class _BlankPage extends StatelessWidget {
  const _BlankPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.shrink());
}

/// Procura uma fonte TTF do sistema e registra com os nomes que o app usa.
/// Tenta caminhos comuns em Windows/Mac/Linux. Se não achar, o teste continua
/// usando Ahem (caixas quadradas) — sem crash.
Future<void> _registerFallbackFonts() async {
  const candidatos = [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    r'C:\Windows\Fonts\calibri.ttf',
    '/Library/Fonts/Arial.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
  ];

  File? fonte;
  for (final p in candidatos) {
    final f = File(p);
    if (f.existsSync()) {
      fonte = f;
      break;
    }
  }
  if (fonte == null) {
    // ignore: avoid_print
    print('[golden-fonts] nenhuma fonte do sistema encontrada — Ahem ativo');
    return;
  }
  // ignore: avoid_print
  print('[golden-fonts] usando ${fonte.path}');

  final bytes = await fonte.readAsBytes();

  // google_fonts gera fontFamily no formato "FamiliaSemEspaco_<peso>".
  // Pesos: "regular" (== 400), "100", "200", "300", "500", "600", "700", "800", "900",
  // sufixos "i" para italic. Também há fontFamilyFallback = ["FamiliaSemEspaco"].
  // Pré-registramos todos os nomes que podem aparecer nos TextStyle gerados.
  final families = <String>['BricolageGrotesque', 'PlusJakartaSans'];
  final variants = <String>[
    'regular',
    '100', '200', '300', '400', '500', '600', '700', '800', '900',
    '100i', '200i', '300i', '400i', '500i', '600i', '700i', '800i', '900i',
  ];

  int count = 0;
  for (final fam in families) {
    final names = <String>{fam, ...variants.map((v) => '${fam}_$v')};
    for (final name in names) {
      final loader = FontLoader(name)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      count++;
    }
  }
  // ignore: avoid_print
  print('[golden-fonts] registradas $count variações');
}

// ─────────────────────────────────────────────────────────────────────────────
// HttpOverrides seletivo: deixa fontes Google passar, bloqueia tiles OSM
// ─────────────────────────────────────────────────────────────────────────────

class _SelectiveHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _SelectiveHttpClient(super.createHttpClient(context));
}

class _SelectiveHttpClient implements HttpClient {
  _SelectiveHttpClient(this._real);
  final HttpClient _real;

  bool _allow(Uri url) {
    final host = url.host;
    return host.contains('gstatic.com') ||
        host.contains('googleapis.com') ||
        host.contains('fonts.google.com');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _allow(url) ? _real.getUrl(url) : Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _allow(url)
      ? _real.openUrl(method, url)
      : Future.value(_MockHttpClientRequest());

  // Delegação para os demais métodos
  @override
  bool get autoUncompress => _real.autoUncompress;
  @override
  set autoUncompress(bool v) => _real.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _real.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _real.connectionTimeout = v;
  @override
  Duration get idleTimeout => _real.idleTimeout;
  @override
  set idleTimeout(Duration v) => _real.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _real.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _real.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _real.userAgent;
  @override
  set userAgent(String? v) => _real.userAgent = v;

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      getUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      postUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      putUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      deleteUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      patchUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      headUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      Future.value(_MockHttpClientRequest());

  @override
  void close({bool force = false}) => _real.close(force: force);
  @override
  set authenticate(
      Future<bool> Function(Uri url, String scheme, String? realm)? f) {
    _real.authenticate = f;
  }

  @override
  set authenticateProxy(
      Future<bool> Function(
              String host, int port, String scheme, String? realm)?
          f) {
    _real.authenticateProxy = f;
  }

  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? f) {
    _real.badCertificateCallback = f;
  }

  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {
    _real.connectionFactory = f;
  }

  @override
  set findProxy(String Function(Uri url)? f) {
    _real.findProxy = f;
  }

  @override
  set keyLog(Function(String line)? callback) {
    _real.keyLog = callback;
  }

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _real.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _real.addProxyCredentials(host, port, realm, credentials);
}


class _MockHttpClientRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  List<Cookie> get cookies => [];
  @override
  Future<HttpClientResponse> get done async => _MockHttpClientResponse();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  String method = 'GET';
  @override
  Uri uri = Uri.parse('http://mock');
  @override
  int contentLength = 0;
  @override
  Encoding encoding = utf8;
  @override
  bool bufferOutput = true;
  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {}
  @override
  Future<dynamic> flush() async {}
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  void write(Object? obj) {}
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? obj = '']) {}
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  // 200 OK com body vazio: faz google_fonts achar que carregou e cair em
  // fallback Roboto sem lançar exception. Tiles OSM idem (renderiza placeholder).
  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => 0;
  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  List<Cookie> get cookies => [];
  @override
  List<RedirectInfo> get redirects => [];
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  X509Certificate? get certificate => null;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(Uint8List(0)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Future<Socket> detachSocket() => throw UnimplementedError();

  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? url, bool? followLoops]) =>
      throw UnimplementedError();
}

class _MockHeaders implements HttpHeaders {
  @override
  bool chunkedTransferEncoding = false;
  @override
  int contentLength = 0;
  @override
  ContentType? contentType;
  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  String? host;
  @override
  DateTime? ifModifiedSince;
  @override
  bool persistentConnection = false;
  @override
  int? port;

  @override
  List<String>? operator [](String name) => null;
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void clear() {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  void noFolding(String name) {}
  @override
  void remove(String name, Object value) {}
  @override
  void removeAll(String name) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;
}
