import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Card de estatística — rótulo, valor principal e subtexto.
/// Fiel ao .stat do protótipo.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.sub,
    this.subColor,
    super.key,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: tsJakarta(9, FontWeight.w700,
                color: AppColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: tsBricolage(18, FontWeight.w800,
                  color: AppColors.ink),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: tsJakarta(8.5, FontWeight.w700,
                  color: subColor ?? AppColors.good),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
