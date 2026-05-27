import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Perfil de usuário — define o conjunto de itens da barra inferior
enum UserType { lojista, motoboy }

/// Barra de navegação inferior branca com quatro itens por perfil.
///
/// Lojista : Início · Agenda · Turnos · Perfil
/// Motoboy : Início · Turnos · Carteira · Perfil
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.userType,
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final UserType userType;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _lojista = [
    _NavItem(icon: Icons.home_outlined,              label: 'Início'),
    _NavItem(icon: Icons.calendar_month_outlined,    label: 'Agenda'),
    _NavItem(icon: Icons.local_shipping_outlined,    label: 'Turnos'),
    _NavItem(icon: Icons.person_outline_rounded,     label: 'Perfil'),
  ];

  static const _motoboy = [
    _NavItem(icon: Icons.home_outlined,                    label: 'Início'),
    _NavItem(icon: Icons.two_wheeler_outlined,             label: 'Turnos'),
    _NavItem(icon: Icons.account_balance_wallet_outlined,  label: 'Carteira'),
    _NavItem(icon: Icons.person_outline_rounded,           label: 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = userType == UserType.lojista ? _lojista : _motoboy;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line, width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(items.length, (i) {
              return Expanded(
                child: _NavTap(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

@immutable
class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _NavTap extends StatelessWidget {
  const _NavTap({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.teal : AppColors.muted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 19, color: color),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: tsJakarta(8, FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          AnimatedOpacity(
            opacity: selected ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.teal,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
