import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../models/usuario.dart';
import '../routes/app_routes.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/desktop/app_topbar.dart';
import '../widgets/desktop/content_grid.dart';
import '../widgets/stat_card.dart';

/// Preview do shell responsivo (Fase 0) — NÃO faz parte do app.
/// Rodar com: flutter run -t lib/dev/shell_preview_main.dart -d chrome
void main() {
  runApp(const _ShellPreviewApp());
}

const _lojistaDemo = Usuario(
  id: 1,
  nome: 'Cláudia Oliveira',
  email: 'claudia@demo.dev',
  telefone: '41 99999-0000',
  tipo: TipoUsuario.lojista,
  nomeFantasia: 'Hamburgueria da Cláudia',
);

const _motoboyDemo = Usuario(
  id: 2,
  nome: 'Ricardo Souza',
  email: 'ricardo@demo.dev',
  telefone: '41 98888-0000',
  tipo: TipoUsuario.motoboy,
  mediaAvaliacao: 4.7,
  veiculoModelo: 'CG 160 Titan',
);

class _ShellPreviewApp extends StatelessWidget {
  const _ShellPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<AuthService>(
          create: (ctx) => AuthService(ctx.read<ApiService>())
            ..atualizarUsuarioLocal(_lojistaDemo),
        ),
      ],
      child: MaterialApp(
        title: 'MotoShift — preview do shell',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: AppRoutes.dashboardLojista,
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => const ShellPreviewScreen(),
        ),
      ),
    );
  }
}

const _titulos = <String, String>{
  AppRoutes.dashboardLojista: 'Início',
  AppRoutes.dashboardMotoboy: 'Início',
  AppRoutes.agenda: 'Agenda',
  AppRoutes.turnosLojista: 'Turnos',
  AppRoutes.turnosDisponiveis: 'Turnos disponíveis',
  AppRoutes.carteira: 'Carteira',
  AppRoutes.minhasAvaliacoes: 'Minhas avaliações',
  AppRoutes.perfil: 'Perfil',
};

class ShellPreviewScreen extends StatelessWidget {
  const ShellPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuario!;
    final ehLojista = usuario.tipo == TipoUsuario.lojista;
    final rotaBruta = ModalRoute.of(context)?.settings.name;
    final rota = _titulos.containsKey(rotaBruta)
        ? rotaBruta!
        : (ehLojista
            ? AppRoutes.dashboardLojista
            : AppRoutes.dashboardMotoboy);
    final titulo = _titulos[rota] ?? 'Início';
    final nome = usuario.nome.split(' ').first;

    return AdaptiveScaffold(
      header: AppHeader.greeting(
        greeting: 'Boa noite,',
        name: nome,
        avatarInitials: nome.substring(0, 2).toUpperCase(),
      ),
      bottomNav: AppBottomNav(
        userType: ehLojista ? UserType.lojista : UserType.motoboy,
        currentIndex: 0,
        onTap: (_) {},
      ),
      body: _MobileBody(onTrocarPapel: () => _trocarPapel(context)),
      desktopTitle: titulo,
      desktopSubtitle: ehLojista
          ? 'Boa noite, $nome · preview do shell (Fase 0)'
          : 'Boa noite, $nome · 1 turno em andamento',
      desktopNotificationCount: 4,
      desktopPrimaryAction: ehLojista
          ? TopbarPrimaryButton(
              label: 'Publicar turno', icon: Icons.add, onTap: () {})
          : null,
      desktopSelectedRoute: rota,
      desktopBody: _DesktopBody(onTrocarPapel: () => _trocarPapel(context)),
    );
  }

  void _trocarPapel(BuildContext context) {
    final auth = context.read<AuthService>();
    final ehLojista = auth.usuario?.tipo == TipoUsuario.lojista;
    auth.atualizarUsuarioLocal(ehLojista ? _motoboyDemo : _lojistaDemo);
    Navigator.pushReplacementNamed(
      context,
      ehLojista ? AppRoutes.dashboardMotoboy : AppRoutes.dashboardLojista,
    );
  }
}

class _DesktopBody extends StatelessWidget {
  const _DesktopBody({required this.onTrocarPapel});

  final VoidCallback onTrocarPapel;

  @override
  Widget build(BuildContext context) {
    return ContentGrid(
      children: [
        const GridCol(
            span: 3,
            child: StatCard(
                label: 'Turnos ativos', value: '6', sub: '2 começam hoje')),
        const GridCol(
            span: 3,
            child: StatCard(
                label: 'Gasto no mês',
                value: r'R$ 2.480',
                sub: '21 turnos pagos',
                subColor: AppColors.muted)),
        const GridCol(
            span: 3,
            child: StatCard(
                label: 'Entregadores', value: '9', sub: '4 recorrentes')),
        const GridCol(
            span: 3,
            child: StatCard(
                label: 'Avaliação',
                value: '4,8',
                sub: '★ recebida · 34 notas',
                subColor: AppColors.amber)),
        GridCol(span: 8, child: _placeholder('Gráfico — entra na Fase 1', 260)),
        GridCol(
            span: 4,
            child: _placeholder('Próximos turnos — entra na Fase 1', 260)),
        GridCol(
          span: 12,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TopbarSecondaryButton(
              label: 'Alternar papel (lojista/motoboy)',
              icon: Icons.swap_horiz_outlined,
              onTap: onTrocarPapel,
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(String label, double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Center(
        child: Text(label,
            style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
      ),
    );
  }
}

class _MobileBody extends StatelessWidget {
  const _MobileBody({required this.onTrocarPapel});

  final VoidCallback onTrocarPapel;

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final faixa = context.isMobile
        ? 'mobile (< 600)'
        : context.isTablet
            ? 'tablet (600–1023)'
            : 'desktop (≥ 1024)';
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      children: [
        const Row(
          children: [
            Expanded(
                child: StatCard(
                    label: 'Turnos ativos', value: '6', sub: '2 hoje')),
            SizedBox(width: 10),
            Expanded(
                child: StatCard(
                    label: 'Gasto mês',
                    value: r'R$ 2.480',
                    sub: '21 pagos',
                    subColor: AppColors.muted)),
            SizedBox(width: 10),
            Expanded(
                child:
                    StatCard(label: 'Avaliação', value: '4,8', sub: '★ 34')),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line, width: 1.5),
          ),
          child: Text(
            'Preview do shell (Fase 0)\n'
            'Largura atual: ${largura.round()}px → $faixa\n'
            'Nesta faixa vale o AppScaffold original.',
            style: tsJakarta(13, FontWeight.w600, color: AppColors.text,
                height: 1.6),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onTrocarPapel,
          child: const Text('Alternar papel (lojista/motoboy)'),
        ),
      ],
    );
  }
}
