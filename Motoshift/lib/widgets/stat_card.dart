import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Escala do [StatCard].
///
/// [compact] é o card do mobile — a métrica cabe três por linha em 390px.
/// [large] é o KPI do desktop: mesma anatomia, tipografia e respiro maiores,
/// com ícone à direita do rótulo (artboards 3 e 4 do protótipo v2).
enum StatCardSize { compact, large }

/// Card de estatística — rótulo, valor principal e subtexto.
/// Fiel ao .stat do protótipo.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.sub,
    this.subColor,
    this.icon,
    this.iconColor,
    this.size = StatCardSize.compact,
    this.minHeight,
    super.key,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? subColor;

  /// Ícone à direita do rótulo. Só aparece em [StatCardSize.large].
  final IconData? icon;
  final Color? iconColor;
  final StatCardSize size;

  /// Altura mínima do card. Usada para igualar a altura de uma linha de KPIs
  /// no desktop, onde o grid do protótipo estica todos à altura do mais alto.
  final double? minHeight;

  bool get _large => size == StatCardSize.large;

  @override
  Widget build(BuildContext context) {
    final gap = _large ? 8.0 : 4.0;

    return Container(
      constraints:
          minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_large ? 16 : 14),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      padding: _large
          ? const EdgeInsets.symmetric(horizontal: 18, vertical: 16)
          : const EdgeInsets.fromLTRB(11, 12, 11, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLabel(),
          SizedBox(height: gap),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: tsBricolage(_large ? 26 : 18, FontWeight.w800,
                  color: AppColors.ink),
            ),
          ),
          if (sub != null) ...[
            SizedBox(height: gap),
            Text(
              sub!,
              style: tsJakarta(_large ? 11 : 8.5, FontWeight.w700,
                  color: subColor ?? AppColors.good),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabel() {
    final texto = Text(
      label.toUpperCase(),
      style: _large
          ? tsJakarta(11, FontWeight.w700, color: AppColors.muted)
              .copyWith(letterSpacing: 11 * .08)
          : tsJakarta(9, FontWeight.w700, color: AppColors.muted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (!_large || icon == null) return texto;

    return Row(
      children: [
        Expanded(child: texto),
        const SizedBox(width: 8),
        Icon(icon, size: 18, color: iconColor ?? AppColors.teal),
      ],
    );
  }
}
