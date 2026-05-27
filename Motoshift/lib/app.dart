import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/repositories/historico_repository_impl.dart';
import 'data/repositories/pedido_repository_impl.dart';
import 'presentation/providers/historico_provider.dart';
import 'presentation/providers/pedido_provider.dart';
import 'presentation/providers/turno_provider.dart';
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
import 'views/stubs/stub_screens.dart';

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
      ],
      child: MaterialApp(
        title: 'Moto Shift',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.splash,
        routes: {
          // Core
          AppRoutes.splash:    (_) => const SplashScreen(),
          AppRoutes.login:     (_) => const LoginScreen(),
          AppRoutes.cadastro:  (_) => const CadastroScreen(),

          // Dashboards
          AppRoutes.dashboardMotoboy: (_) => const DashboardMotoboyScreen(),
          AppRoutes.dashboardLojista: (_) => const DashboardLojistScreen(),

          // Fluxo Lojista
          AppRoutes.publicarTurno: (_) => const AgendarTurnoScreen(),
          AppRoutes.turnoLojista:  (_) => const TurnoLojistScreen(),
          AppRoutes.turnosLojista: (_) => const TurnosLojistaListaScreen(),

          // Fluxo Motoboy
          AppRoutes.turnosDisponiveis: (_) => const MeusTurnosScreen(),
          AppRoutes.detalheTurno:      (_) => const DetalheTurnoScreen(),
          AppRoutes.carteira:          (_) => const CarteiraScreen(),

          // Compartilhadas
          AppRoutes.agenda:    (_) => const AgendaScreen(),
          AppRoutes.avaliacao: (_) => const AvaliacaoScreen(),
          AppRoutes.perfil:    (_) => const PerfilScreen(),

          // Perfil — sub-páginas
          AppRoutes.dadosPessoais:    (_) => const DadosPessoaisScreen(),
          AppRoutes.cnhVeiculo:       (_) => const CnhVeiculoScreen(),
          AppRoutes.notificacoes:     (_) => const NotificacoesScreen(),
          AppRoutes.minhasAvaliacoes: (_) => const MinhasAvaliacoesScreen(),
          AppRoutes.historicoTurnos:  (_) => const HistoricoTurnosScreen(),
          AppRoutes.sacarPix:         (_) => const SacarPixScreen(),
          AppRoutes.esqueceuSenha:    (_) => const EsqueceuSenhaScreen(),

          // Legadas
          AppRoutes.meusTurnos:       (_) => const MeusTurnosScreen(),
          AppRoutes.agendarTurno:     (_) => const AgendarTurnoScreen(),
          AppRoutes.historico:        (_) => const HistoricoScreen(),
          AppRoutes.solicitarServico: (_) => const SolicitarServicoScreen(),
        },
      ),
    );
  }
}
