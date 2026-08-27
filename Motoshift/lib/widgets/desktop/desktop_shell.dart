import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../presentation/providers/notificacao_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'app_sidebar.dart';
import 'app_topbar.dart';

/// Shell desktop (>= 1024px): sidebar fixa de 240px + coluna de conteúdo com
/// topbar de 72px. O usuário logado (nome, iniciais, papel) vem do AuthService.
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    required this.title,
    required this.body,
    this.subtitle,
    this.primaryAction,
    this.notificationCount = 0,
    this.onNotificationsTap,
    this.selectedRoute,
    this.showBack,
    this.onBack,
    super.key,
  });

  final String title;
  final Widget body;
  final String? subtitle;
  final Widget? primaryAction;
  final int notificationCount;
  final VoidCallback? onNotificationsTap;

  /// Rota destacada na sidebar; por padrão usa a rota atual do Navigator.
  final String? selectedRoute;

  /// Mostra a seta de voltar na topbar. Nulo = decide sozinho, pelo
  /// `Navigator.canPop()` — que é exatamente a pergunta "tem para onde
  /// voltar?". Telas de raiz (dashboards, itens de sidebar alcançados por
  /// `pushReplacementNamed`) não podem dar pop, então não ganham a seta.
  final bool? showBack;

  /// Substitui o `Navigator.maybePop` padrão.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuario;
    final ehLojista = usuario?.tipo == TipoUsuario.lojista;

    final items =
        ehLojista ? SidebarItems.lojista() : SidebarItems.motoboy();
    final rotaAtual =
        selectedRoute ?? ModalRoute.of(context)?.settings.name;

    final podeVoltar = showBack ?? Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.surface2,
      body: Row(
        children: [
          AppSidebar(
            items: items,
            selectedRoute: rotaAtual,
            userName: usuario?.nome ?? '',
            userSubtitle: _subtitleDoUsuario(usuario),
            userInitials: _iniciais(usuario?.nome),
            onLogout: () => _confirmarSaida(context),
          ),
          Expanded(
            child: Column(
              children: [
                AppTopbar(
                  title: title,
                  subtitle: subtitle,
                  primaryAction: primaryAction,
                  onBack: podeVoltar
                      ? (onBack ?? () => Navigator.maybePop(context))
                      : null,
                  // A contagem vem do provider quando a tela não informa uma
                  // própria — assim o sino tem badge em toda tela do desktop.
                  notificationCount: notificationCount > 0
                      ? notificationCount
                      : context.watch<NotificacaoProvider>().naoLidas,
                  onNotificationsTap: onNotificationsTap ??
                      () => Navigator.pushNamed(
                          context, AppRoutes.notificacoes),
                  avatarInitials: _iniciais(usuario?.nome),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Lojista: nome fantasia; motoboy: nota e moto — como no canvas.
  String _subtitleDoUsuario(Usuario? usuario) {
    if (usuario == null) return '';
    if (usuario.tipo == TipoUsuario.lojista) {
      return usuario.nomeFantasia ?? usuario.email;
    }
    final nota = usuario.mediaAvaliacao;
    final partes = [
      if (nota != null) '★ ${nota.toStringAsFixed(2).replaceAll('.', ',')}',
      if (usuario.veiculoModelo != null) usuario.veiculoModelo!,
    ];
    return partes.isEmpty ? usuario.email : partes.join(' · ');
  }

  /// Duas primeiras letras do primeiro nome ("CL", "RI"), como no canvas e
  /// no avatar do header mobile.
  String _iniciais(String? nome) {
    final primeiro = (nome ?? '').trim().split(RegExp(r'\s+')).first;
    if (primeiro.isEmpty) return '·';
    return primeiro.length >= 2
        ? primeiro.substring(0, 2).toUpperCase()
        : primeiro.toUpperCase();
  }

  Future<void> _confirmarSaida(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sair',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          'Deseja realmente sair da sua conta?',
          style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sair',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      context.read<AuthService>().logout();
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }
}
