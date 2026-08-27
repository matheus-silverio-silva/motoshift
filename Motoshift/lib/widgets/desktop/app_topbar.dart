import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Topbar desktop de 72px — fundo branco, borda inferior 1.5px na cor da linha,
/// padding horizontal 24. Voltar (quando há para onde), título e subtítulo à
/// esquerda; à direita ação primária, sino de notificações com badge e avatar.
class AppTopbar extends StatelessWidget {
  const AppTopbar({
    required this.title,
    this.subtitle,
    this.primaryAction,
    this.notificationCount = 0,
    this.onNotificationsTap,
    this.avatarInitials,
    this.onBack,
    super.key,
  });

  static const double height = 72;

  final String title;
  final String? subtitle;

  /// Botão de ação da tela (ex.: [TopbarPrimaryButton]).
  final Widget? primaryAction;
  final int notificationCount;
  final VoidCallback? onNotificationsTap;
  final String? avatarInitials;

  /// Seta de voltar à esquerda do título. Nula = a tela não tem para onde
  /// voltar (é raiz), e o botão não é montado.
  ///
  /// O equivalente mobile é o `AppHeader.back`. Sem isto, telas empilhadas no
  /// desktop (notificações, carteira, histórico…) viravam beco sem saída: a
  /// única saída era a sidebar, que faz `pushReplacementNamed`.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1.5)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            _TopbarIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Voltar',
              onTap: onBack,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tsBricolage(20, FontWeight.w800, color: AppColors.ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(11.5, FontWeight.w500,
                        color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (primaryAction != null) ...[
            primaryAction!,
            const SizedBox(width: 12),
          ],
          _NotificationBell(
            count: notificationCount,
            onTap: onNotificationsTap,
          ),
          if (avatarInitials != null) ...[
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  avatarInitials!,
                  style: tsBricolage(14, FontWeight.w800,
                      color: const Color(0xFFFFFFFF)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Quadrado de 44px da topbar — fundo surface2, borda 1.5px, raio 12.
/// É a moldura do sino e do voltar; [overlay] empilha o badge por cima.
class _TopbarIconButton extends StatelessWidget {
  const _TopbarIconButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.overlay,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final botao = Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppColors.surface3,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line, width: 1.5),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(icon, size: 20, color: AppColors.tealDeep),
              ),
              if (overlay != null) overlay!,
            ],
          ),
        ),
      ),
    );

    return tooltip == null ? botao : Tooltip(message: tooltip!, child: botao);
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _TopbarIconButton(
      icon: Icons.notifications_outlined,
      tooltip: 'Notificações',
      onTap: onTap,
      overlay: count == 0
          ? null
          : Positioned(
              top: 7,
              right: 8,
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Center(
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: tsJakarta(9.5, FontWeight.w800,
                        color: AppColors.onTertiary),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Botão âmbar da topbar (ação primária da tela), fiel ao canvas:
/// 44px de altura, raio 14, sombra âmbar difusa.
class TopbarPrimaryButton extends StatelessWidget {
  const TopbarPrimaryButton({
    required this.label,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0xBFF6A623), // rgba(246,166,35,.75)
            blurRadius: 22,
            spreadRadius: -10,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: AppColors.amber,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.onTertiary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: tsJakarta(13.5, FontWeight.w700,
                      color: AppColors.onTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão secundário da topbar — fundo teal suave, texto teal escuro.
class TopbarSecondaryButton extends StatelessWidget {
  const TopbarSecondaryButton({
    required this.label,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tealSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.tealDeep),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: tsJakarta(13, FontWeight.w700,
                    color: AppColors.tealDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
