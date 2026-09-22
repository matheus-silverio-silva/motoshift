import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/nav_config.dart';
import '../services/auth_service.dart';
import '../theme/breakpoints.dart';
import 'app_bottom_nav.dart';
import 'app_nav_drawer.dart';
import 'app_scaffold.dart';
import 'desktop/desktop_shell.dart';

/// Scaffold que escolhe o shell pelo breakpoint:
///   - mobile e tablet → [AppScaffold];
///   - desktop (>= 1024px) → [DesktopShell], quando a tela informa
///     [desktopTitle]; sem ele a tela ainda não foi migrada e o
///     [AppScaffold] continua valendo em qualquer largura.
///
/// <h3>Quem monta a navegação</h3>
/// **Este widget**, a partir de [rotaDaSecao] e do papel de quem está logado.
/// Antes cada tela montava a sua: passava `AppBottomNav(userType: …, currentIndex:
/// …, onTap: _onNav)` com um `switch` próprio, e escrevia `desktopSelectedRoute`
/// à mão. Sete telas carregavam esse switch, uma passava o papel errado, e duas
/// escreveram a rota de destaque errada — o Saldo do lojista marcava "Carteira",
/// item que nem existe no menu dele.
///
/// Agora a tela declara uma coisa só: **em que seção do menu ela está**. Se
/// [rotaDaSecao] for nulo, a tela é uma sub-página (detalhe, formulário) e não
/// ganha barra nem gaveta — só a seta de voltar.
///
/// <h3>Gaveta e barra são decisões separadas</h3>
/// A gaveta aparece em **toda** tela de seção; a barra inferior, só nas quatro
/// que o [NavConfig] marca. Isso era um bug: a regra antiga dava gaveta apenas
/// a quem tinha barra, então Notas fiscais, Avaliações, Histórico, Notificações
/// e Saldo ficavam sem menu — e como o item do menu substituía a pilha, a seta
/// de voltar dava `pop` na única rota e a tela ficava em branco.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.header,
    required this.body,
    this.rotaDaSecao,
    this.floatingActionButton,
    this.desktopTitle,
    this.desktopSubtitle,
    this.desktopBody,
    this.desktopPrimaryAction,
    this.desktopNotificationCount = 0,
    this.desktopOnNotificationsTap,
    this.desktopShowBack,
    this.desktopOnBack,
    super.key,
  });

  // ── API do AppScaffold (mobile/tablet) ────────────────────────────────────
  final Widget header;
  final Widget body;
  final Widget? floatingActionButton;

  /// A seção do menu a que esta tela pertence.
  ///
  /// Determina três coisas de uma vez: o item destacado no menu (lateral no
  /// desktop, gaveta no celular), se a tela tem barra inferior, e se ela tem
  /// gaveta. Nulo = sub-página: nada destacado, sem barra, sem gaveta.
  final String? rotaDaSecao;

  // ── Desktop ───────────────────────────────────────────────────────────────
  /// Título da topbar. Obrigatório para a tela ganhar o shell desktop.
  final String? desktopTitle;
  final String? desktopSubtitle;

  /// Corpo específico do desktop (ex.: [ContentGrid]); se nulo, usa [body].
  final Widget? desktopBody;
  final Widget? desktopPrimaryAction;
  final int desktopNotificationCount;
  final VoidCallback? desktopOnNotificationsTap;

  /// Seta de voltar na topbar. Nulo = o shell decide pelo `canPop()`.
  final bool? desktopShowBack;
  final VoidCallback? desktopOnBack;

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop && desktopTitle != null) {
      return DesktopShell(
        title: desktopTitle!,
        subtitle: desktopSubtitle,
        body: desktopBody ?? body,
        primaryAction: desktopPrimaryAction,
        notificationCount: desktopNotificationCount,
        onNotificationsTap: desktopOnNotificationsTap,
        selectedRoute: rotaDaSecao,
        showBack: desktopShowBack,
        onBack: desktopOnBack,
      );
    }

    final papel = context.watch<AuthService>().usuario?.tipo;
    final secao = rotaDaSecao;

    // A barra inferior só existe nos quatro atalhos do papel. Uma tela de
    // seção que não está entre eles (Histórico, Notas fiscais…) fica sem
    // barra, mas COM gaveta — que é a saída dela.
    final temBarra = secao != null &&
        papel != null &&
        NavConfig.barraInferior(papel).any((i) => i.route == secao);

    return AppScaffold(
      header: header,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNav: temBarra ? AppBottomNav(rotaAtual: secao) : null,
      drawer: secao == null ? null : AppNavDrawer(rotaDaSecao: secao),
    );
  }
}
