import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/usuario.dart';
import '../presentation/providers/notificacao_provider.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/iniciais.dart';
import 'desktop/app_sidebar.dart';

/// O mesmo menu da barra lateral do desktop, como gaveta no celular.
///
/// Existe para cumprir a regra de que toda função do app está no menu da
/// esquerda em qualquer tamanho de tela. A barra inferior continua com os
/// quatro atalhos do dia a dia; o resto — notas fiscais, avaliações,
/// histórico, notificações — estava disperso dentro do Perfil e agora tem um
/// lugar só, igual em celular e desktop.
///
/// Reaproveita [AppSidebar] de propósito: dois menus com a mesma intenção
/// divergem no primeiro item que alguém esquecer de copiar.
class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({this.selectedRoute, super.key});

  /// Rota destacada. Nulo = a rota atual do Navigator.
  final String? selectedRoute;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuario;
    if (usuario == null) return const SizedBox.shrink();

    final naoLidas = context.watch<NotificacaoProvider>().naoLidas;
    final badge = naoLidas == 0 ? null : (naoLidas > 9 ? '9+' : '$naoLidas');

    final sections = usuario.tipo == TipoUsuario.lojista
        ? SidebarItems.lojista(badgeNotificacoes: badge)
        : SidebarItems.motoboy(badgeNotificacoes: badge);

    final rotaAtual = selectedRoute ?? ModalRoute.of(context)?.settings.name;

    return Drawer(
      width: AppSidebar.width,
      backgroundColor: AppColors.tealDeep,
      child: AppSidebar(
        sections: sections,
        selectedRoute: rotaAtual,
        userName: usuario.nome,
        userSubtitle: _subtitulo(usuario),
        userInitials: iniciaisDe(usuario.nome),
        // Fecha a gaveta antes de navegar: sem isso ela fica aberta por cima
        // da tela nova até o usuário arrastar de volta.
        onSelect: (item) {
          Navigator.pop(context);
          if (item.route == rotaAtual) return;
          Navigator.pushReplacementNamed(context, item.route);
        },
        onLogout: () {
          Navigator.pop(context);
          context.read<AuthService>().logout();
          Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.login, (_) => false);
        },
      ),
    );
  }

  String _subtitulo(Usuario usuario) {
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
}

