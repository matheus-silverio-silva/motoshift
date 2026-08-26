import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// KPI de saldo do desktop — mesmo bloco dos demais KPIs, mas em gradiente
/// teal, com círculo decorativo e um botão de ação (artboard 4 do protótipo).
class WalletKpiCard extends StatelessWidget {
  const WalletKpiCard({
    required this.label,
    required this.value,
    this.sub,
    this.actionLabel,
    this.onAction,
    this.minHeight,
    super.key,
  });

  final String label;
  final String value;
  final String? sub;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Altura mínima — ver [StatCard.minHeight].
  final double? minHeight;

  static const Color _softText = Color(0xFFBFE5E3);

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      constraints:
          minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -28,
            child: Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(
                color: Color(0x12FFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(11, FontWeight.w700, color: _softText)
                            .copyWith(letterSpacing: 11 * .08),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 18, color: _softText),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: tsBricolage(26, FontWeight.w800,
                        color: const Color(0xFFFFFFFF)),
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(11, FontWeight.w600, color: _softText),
                  ),
                ],
                if (actionLabel != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: onAction,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                actionLabel!,
                                style: tsJakarta(11.5, FontWeight.w700,
                                    color: const Color(0xFF3A2603)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
