import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Card branco do desktop: raio 16, borda 1.5 na cor da linha, sombra suave.
/// Cabeçalho opcional com título, subtítulo e link de ação à direita.
class PanelCard extends StatelessWidget {
  const PanelCard({
    required this.child,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    this.gap = 12,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// Link de texto à direita do título (ex.: "Ver agenda").
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Widget à direita do título, no lugar do link (ex.: uma pílula).
  final Widget? trailing;

  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            _buildHeader(),
            SizedBox(height: gap),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tsBricolage(16, FontWeight.w800, color: AppColors.ink),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tsJakarta(12, FontWeight.w400, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null)
          trailing!
        else if (actionLabel != null) ...[
          const SizedBox(width: 12),
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                actionLabel!,
                style: tsJakarta(12, FontWeight.w700, color: AppColors.teal),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
