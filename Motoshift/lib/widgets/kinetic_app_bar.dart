import 'package:flutter/material.dart';
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
          ],
        ),
      ),
    );
  }
}
