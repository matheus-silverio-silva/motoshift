import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Variante visual do StatusPill
enum PillVariant { teal, amber, good, ghost }

/// Pílula de status colorida. Fiel ao .pill do protótipo.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.variant = PillVariant.ghost,
    this.leadingDot = false,
    super.key,
  });

  final String label;
  final PillVariant variant;
  final bool leadingDot;

  Color get _bg => switch (variant) {
        PillVariant.teal  => AppColors.tealSoft,
        PillVariant.amber => AppColors.amberSoft,
        PillVariant.good  => AppColors.goodSoft,
        PillVariant.ghost => AppColors.surface3,
      };

  Color get _fg => switch (variant) {
        PillVariant.teal  => AppColors.tealDeep,
        PillVariant.amber => const Color(0xFF9A6206),
        PillVariant.good  => const Color(0xFF0F6E4E),
        PillVariant.ghost => AppColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingDot) ...[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 5),
              decoration:
                  BoxDecoration(color: _fg, shape: BoxShape.circle),
            ),
          ],
          Text(
            label,
            style: tsJakarta(9.5, FontWeight.w700, color: _fg),
          ),
        ],
      ),
    );
  }
}
