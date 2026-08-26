import 'package:flutter/material.dart';
import '../theme/breakpoints.dart';
import 'app_scaffold.dart';
import 'desktop/desktop_shell.dart';

/// Scaffold que escolhe o shell pelo breakpoint:
///   - mobile e tablet → [AppScaffold] (intocado);
///   - desktop (>= 1024px) → [DesktopShell], quando a tela informa
///     [desktopTitle]; sem ele a tela ainda não foi migrada e o
///     [AppScaffold] continua valendo em qualquer largura.
///
/// A API mobile é idêntica à do [AppScaffold] — migrar uma tela é trocar
/// `AppScaffold(` por `AdaptiveScaffold(` e acrescentar os parâmetros
/// `desktop*`.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.header,
    required this.body,
    this.bottomNav,
    this.floatingActionButton,
    this.desktopTitle,
    this.desktopSubtitle,
    this.desktopBody,
    this.desktopPrimaryAction,
    this.desktopNotificationCount = 0,
    this.desktopOnNotificationsTap,
    this.desktopSelectedRoute,
    super.key,
  });

  // ── API do AppScaffold (mobile/tablet) ────────────────────────────────────
  final Widget header;
  final Widget body;
  final Widget? bottomNav;
  final Widget? floatingActionButton;

  // ── Desktop ───────────────────────────────────────────────────────────────
  /// Título da topbar. Obrigatório para a tela ganhar o shell desktop.
  final String? desktopTitle;
  final String? desktopSubtitle;

  /// Corpo específico do desktop (ex.: [ContentGrid]); se nulo, usa [body].
  final Widget? desktopBody;
  final Widget? desktopPrimaryAction;
  final int desktopNotificationCount;
  final VoidCallback? desktopOnNotificationsTap;
  final String? desktopSelectedRoute;

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
        selectedRoute: desktopSelectedRoute,
      );
    }
    return AppScaffold(
      header: header,
      body: body,
      bottomNav: bottomNav,
      floatingActionButton: floatingActionButton,
    );
  }
}
