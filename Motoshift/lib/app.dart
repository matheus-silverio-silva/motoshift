import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/repositories/historico_repository_impl.dart';
import 'data/repositories/pedido_repository_impl.dart';
import 'presentation/providers/historico_provider.dart';
import 'presentation/providers/pedido_provider.dart';
import 'presentation/providers/turno_provider.dart';
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
        initialRoute: '/splash',
        routes: {
          '/splash': (_) => const SplashScreen(),
          '/login': (_) => const LoginScreen(),
          '/cadastro': (_) => const CadastroScreen(),
          '/dashboard-motoboy': (_) => const DashboardMotoboyScreen(),
          '/dashboard-lojista': (_) => const DashboardLojistScreen(),
          '/agendar-turno': (_) => const AgendarTurnoScreen(),
          '/meus-turnos': (_) => const MeusTurnosScreen(),
          '/carteira': (_) => const CarteiraScreen(),
          '/solicitar-servico': (_) => const SolicitarServicoScreen(),
          '/historico': (_) => const HistoricoScreen(),
          '/agenda': (_) => const AgendaScreen(),
        },
      ),
    );
  }
}
