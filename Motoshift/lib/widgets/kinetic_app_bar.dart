import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// AppBar glassmorphism fiel ao protótipo Urban Kinetic.
/// Fundo translúcido (70% opacidade) com backdrop-blur.
class KineticAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? avatarUrl;
  final VoidCallback? onNotificationTap;

  const KineticAppBar({
    super.key,
    this.avatarUrl,
    this.onNotificationTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  void _confirmarLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Sair da conta',
          style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Tem certeza que deseja desconectar?',
          style: TextStyle(fontFamily: 'Manrope', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthService>().logout();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
            child: const Text(
              'Sair',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.70),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl != null
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.person, color: AppColors.outline),
                    )
                  : const Icon(Icons.person, color: AppColors.outline),
            ),
            const SizedBox(width: 12),
            // Logo
            const Text(
              'Moto Shift',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                color: AppColors.primary,
              ),
            ),
            const Spacer(),
            // Notificações
            GestureDetector(
              onTap: onNotificationTap,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.onSurfaceVariant,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Logout
            GestureDetector(
              onTap: () => _confirmarLogout(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
