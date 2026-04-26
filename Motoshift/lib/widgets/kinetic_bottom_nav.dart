import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum NavItem { dashboard, turnos, carteira }

class KineticBottomNav extends StatelessWidget {
  final NavItem currentItem;
  final ValueChanged<NavItem> onItemSelected;

  const KineticBottomNav({
    super.key,
    required this.currentItem,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.70),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: AppColors.bottomNavShadow,
        border: Border(
          top: BorderSide(
            color: AppColors.onSurfaceVariant.withOpacity(0.10),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavChip(
                icon: Icons.dashboard_rounded,
                label: 'Dashboard',
                selected: currentItem == NavItem.dashboard,
                onTap: () => onItemSelected(NavItem.dashboard),
              ),
              _NavChip(
                icon: Icons.calendar_today_rounded,
                label: 'Shifts',
                selected: currentItem == NavItem.turnos,
                onTap: () => onItemSelected(NavItem.turnos),
              ),
              _NavChip(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Wallet',
                selected: currentItem == NavItem.carteira,
                onTap: () => onItemSelected(NavItem.carteira),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : AppColors.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: selected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
