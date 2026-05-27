import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Item de menu no perfil — ícone + título + subtítulo + chevron.
/// Fiel ao .mrow do protótipo.
class MenuRow extends StatelessWidget {
  const MenuRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.danger = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconBg = danger
        ? const Color(0xFFFBE4E2)
        : AppColors.tealSoft;
    final iconColor =
        danger ? const Color(0xFFC0392B) : AppColors.tealDeep;
    final labelColor =
        danger ? const Color(0xFFC0392B) : AppColors.text;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: tsJakarta(12, FontWeight.w700,
                          color: labelColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!,
                        style: tsJakarta(9, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            if (!danger)
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Color(0xFFBCCCCC)),
          ],
        ),
      ),
    );
  }
}

/// Grupo de MenuRows com borda e separadores internos.
class MenuGroup extends StatelessWidget {
  const MenuGroup({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, color: AppColors.line),
          ],
        ],
      ),
    );
  }
}
