import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'data/repositories/historico_repository_impl.dart';
import 'data/repositories/pedido_repository_impl.dart';
import 'presentation/providers/historico_provider.dart';
import 'presentation/providers/pedido_provider.dart';
import 'presentation/providers/turno_provider.dart';
import 'presentation/providers/turno_selecionado_provider.dart';
import 'routes/app_routes.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'views/login/login_screen.dart';
import 'views/cadastro/cadastro_screen.dart';
import 'views/splash/splash_screen.dart';
import 'views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'views/agendar_turno/agendar_turno_screen.dart';
import 'views/meus_turnos/meus_turnos_screen.dart';
import 'views/carteira/carteira_screen.dart';
import 'views/solicitar_servico/solicitar_servico_screen.dart';
import 'views/historico/historico_screen.dart';
import 'views/agenda/agenda_screen.dart';
import 'views/avaliacao/avaliacao_screen.dart';
import 'views/perfil/perfil_screen.dart';
import 'views/detalhe_turno/detalhe_turno_screen.dart';
import 'views/turno_lojista/turno_lojista_screen.dart';
import 'views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';
import 'views/dados_pessoais/dados_pessoais_screen.dart';
import 'views/cnh_veiculo/cnh_veiculo_screen.dart';
import 'views/minhas_avaliacoes/minhas_avaliacoes_screen.dart';
import 'views/historico_turnos/historico_turnos_screen.dart';
import 'views/stubs/stub_screens.dart';
import 'widgets/auth_guard.dart';
import 'models/usuario.dart';

class MotoShiftApp extends StatelessWidget {
  const MotoShiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Infraestrutura
        Provider<ApiService>(create: (_) => ApiService()),

        // Auth
        ChangeNotifierProxyProvider<ApiService, AuthService>(
          create: (ctx) => AuthService(ctx.read<ApiService>()),
          update: (_, api, prev) => prev ?? AuthService(api),
        ),

        // Pedidos (RF02 / RF03)
        ChangeNotifierProxyProvider<ApiService, PedidoProvider>(
          create: (ctx) => PedidoProvider(
            repo: PedidoRepositoryImpl(ctx.read<ApiService>()),
          ),
          update: (_, api, prev) =>
              prev ?? PedidoProvider(repo: PedidoRepositoryImpl(api)),
        ),

        // Histórico (RF04)
        ChangeNotifierProxyProvider<ApiService, HistoricoProvider>(
          create: (ctx) => HistoricoProvider(
            repo: HistoricoRepositoryImpl(ctx.read<ApiService>()),
          ),
          update: (_, api, prev) =>
              prev ?? HistoricoProvider(repo: HistoricoRepositoryImpl(api)),
        ),

        // Turnos (RF04/RF05/RF06/RF07)
        ChangeNotifierProxyProvider<ApiService, TurnoProvider>(
          create: (ctx) => TurnoProvider(ctx.read<ApiService>()),
          update: (_, api, prev) => prev ?? TurnoProvider(api),
        ),

        // Seleção do master-detail (só usada em telas >= 1024px)
        ChangeNotifierProvider<TurnoSelecionadoProvider>(
          create: (_) => TurnoSelecionadoProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Moto Shift',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: AppRoutes.splash,
        routes: {
          // ── Públicas (sem guard) ──────────────────────────────────────────
          AppRoutes.splash:    (_) => const SplashScreen(),
          AppRoutes.login:     (_) => const LoginScreen(),
          AppRoutes.cadastro:  (_) => const CadastroScreen(),
          AppRoutes.esqueceuSenha: (_) => const EsqueceuSenhaScreen(),

          // ── Dashboards (protegidas por papel) ─────────────────────────────
          AppRoutes.dashboardMotoboy: (_) => const AuthGuard(
                papel: TipoUsuario.motoboy,
                child: DashboardMotoboyScreen(),
              ),
          AppRoutes.dashboardLojista: (_) => const AuthGuard(
                papel: TipoUsuario.lojista,
                child: DashboardLojistScreen(),
              ),

          // ── Fluxo Lojista (papel lojista) ─────────────────────────────────
          AppRoutes.publicarTurno: (_) => const AuthGuard(
                papel: TipoUsuario.lojista,
                child: AgendarTurnoScreen(),
              ),
          AppRoutes.turnoLojista: (_) => const AuthGuard(
                papel: TipoUsuario.lojista,
                child: TurnoLojistScreen(),
              ),
          AppRoutes.turnosLojista: (_) => const AuthGuard(
                papel: TipoUsuario.lojista,
                child: TurnosLojistaListaScreen(),
              ),

          // ── Fluxo Motoboy (papel motoboy) ─────────────────────────────────
          AppRoutes.turnosDisponiveis: (_) => const AuthGuard(
                papel: TipoUsuario.motoboy,
                child: MeusTurnosScreen(),
              ),
          AppRoutes.detalheTurno: (_) => const AuthGuard(
                child: DetalheTurnoScreen(),
              ),
          AppRoutes.carteira: (_) => const AuthGuard(
                papel: TipoUsuario.motoboy,
                child: CarteiraScreen(),
              ),

          // ── Compartilhadas (qualquer autenticado) ─────────────────────────
          AppRoutes.agenda:    (_) => const AuthGuard(child: AgendaScreen()),
          AppRoutes.avaliacao: (_) => const AuthGuard(child: AvaliacaoScreen()),
          AppRoutes.perfil:    (_) => const AuthGuard(child: PerfilScreen()),

          // ── Perfil — sub-páginas (qualquer autenticado) ───────────────────
          AppRoutes.dadosPessoais:    (_) => const AuthGuard(child: DadosPessoaisScreen()),
          AppRoutes.cnhVeiculo:       (_) => const AuthGuard(child: CnhVeiculoScreen()),
          AppRoutes.minhasAvaliacoes: (_) => const AuthGuard(child: MinhasAvaliacoesScreen()),
          AppRoutes.historicoTurnos:  (_) => const AuthGuard(child: HistoricoTurnosScreen()),
          AppRoutes.sacarPix:         (_) => const AuthGuard(papel: TipoUsuario.motoboy, child: SacarPixScreen()),

          // ── Legadas (protegidas) ──────────────────────────────────────────
          AppRoutes.meusTurnos:       (_) => const AuthGuard(child: MeusTurnosScreen()),
          AppRoutes.agendarTurno:     (_) => const AuthGuard(child: AgendarTurnoScreen()),
          AppRoutes.historico:        (_) => const AuthGuard(child: HistoricoScreen()),
          AppRoutes.solicitarServico: (_) => const AuthGuard(child: SolicitarServicoScreen()),
        },
      ),
    );
  }
}
