import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/usuario.dart';
import '../presentation/providers/notificacao_provider.dart';
import '../routes/app_routes.dart';
import '../routes/nav_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/iniciais.dart';
import 'desktop/app_sidebar.dart';

/// O mesmo menu da barra lateral do desktop, como gaveta no celular.
///
/// Existe para cumprir a regra de que toda função do app está no menu da
/// esquerda em qualquer tamanho de tela. A barra inferior continua com os
/// quatro atalhos do dia a dia; o resto — notas fiscais, avaliações,
/// histórico, notificações — tem um lugar só, igual em celular e desktop.
///
/// Reaproveita [AppSidebar] de propósito: dois menus com a mesma intenção
/// divergem no primeiro item que alguém esquecer de copiar.
class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({this.rotaDaSecao, super.key});

  /// A seção destacada. Nulo = derivada da rota atual do Navigator.
  final String? rotaDaSecao;

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuario;
    if (usuario == null) return const SizedBox.shrink();

    final secao = NavConfig.secaoDe(
        rotaDaSecao ?? ModalRoute.of(context)?.settings.name);

    return Drawer(
      width: AppSidebar.width,
      backgroundColor: AppColors.tealDeep,
      child: AppSidebar(
        sections: NavConfig.secoes(usuario.tipo),
        selectedRoute: secao,
        badges: badgesDoMenu(context),
        userName: usuario.nome,
        userSubtitle: _subtitulo(usuario),
        userInitials: iniciaisDe(usuario.nome),
        // Fecha a gaveta antes de navegar: sem isso ela fica aberta por cima
        // da tela nova até o usuário arrastar de volta.
        onSelect: (item) {
          Navigator.pop(context);
          NavConfig.irParaSecao(context, item.route);
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

/// Os contadores do menu, lidos dos providers.
///
/// Fica aqui, e não dentro do [AppSidebar], porque o sidebar é o desenho do
/// menu e não deve saber de onde vêm os números — a gaveta do celular e o
/// shell do desktop chamam esta função e passam o resultado pronto.
Map<NavBadge, String?> badgesDoMenu(BuildContext context) {
  final naoLidas = context.watch<NotificacaoProvider>().naoLidas;
  return {
    NavBadge.notificacoes: _contador(naoLidas),
  };
}

String? _contador(int quantidade) {
  if (quantidade <= 0) return null;
  return quantidade > 9 ? '9+' : '$quantidade';
}
