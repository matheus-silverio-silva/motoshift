import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Título de seção com link opcional "ver mais". Fiel ao .sec-title do protótipo.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: tsBricolage(13, FontWeight.w800, color: AppColors.ink)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: tsJakarta(10, FontWeight.w700,
                    color: AppColors.teal),
              ),
            ),
        ],
      ),
    );
  }
}
