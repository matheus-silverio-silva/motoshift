import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ── WalletHero ────────────────────────────────────────────────────────────────
/// Card hero da carteira — saldo, botão Pix e botão Extrato.
/// Fiel ao .wallet-hero do protótipo.
class WalletHero extends StatelessWidget {
  const WalletHero({
    required this.balance,
    this.onWithdraw,
    this.onExtract,
    super.key,
  });

  final String balance;
  final VoidCallback? onWithdraw;
  final VoidCallback? onExtract;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.walletGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Stack(
        children: [
          // círculo decorativo
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Color(0x12FFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saldo disponível',
                style: tsJakarta(10.5, FontWeight.w600,
                    color: const Color(0xFFBFE5E3)),
              ),
              const SizedBox(height: 3),
              Text(
                balance,
                style: tsBricolage(32, FontWeight.w800,
                    color: const Color(0xFFFFFFFF)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _WalletBtn(
                      label: 'Sacar via Pix',
                      solid: true,
                      onTap: onWithdraw,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WalletBtn(
                      label: 'Extrato',
                      onTap: onExtract,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletBtn extends StatelessWidget {
  const _WalletBtn({required this.label, this.solid = false, this.onTap});
  final String label;
  final bool solid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: solid ? AppColors.amber : const Color(0x29FFFFFF),
          borderRadius: BorderRadius.circular(11),
          border:
              solid ? null : Border.all(color: const Color(0x33FFFFFF), width: 1),
        ),
        child: Center(
          child: Text(
            label,
            style: tsJakarta(10.5, FontWeight.w700,
                color: solid ? AppColors.onTertiary : const Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
  }
}

// ── LedgerRow ────────────────────────────────────────────────────────────────
/// Linha do extrato da carteira. Fiel ao .lrow do protótipo.
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    required this.title,
    required this.date,
    required this.amount,
    required this.isCredit,
    super.key,
  });

  final String title;
  final String date;
  final String amount;

  /// `true` entrada, `false` saída, `null` direção desconhecida — o backend
  /// mandou um tipo de lançamento que o app não conhece, e chutar a seta e a
  /// cor seria mentir sobre para que lado o dinheiro foi.
  final bool? isCredit;

  @override
  Widget build(BuildContext context) {
    // Os dois lados do merge: os três estados vieram da branch de pagamentos
    // (`bool?` — entra, sai, ou não dá para afirmar), e o token no lugar do
    // literal 0xFF9A6206 veio da main.
    final iconColor = switch (isCredit) {
      true => AppColors.good,
      false => AppColors.onTertiaryContainer,
      null => AppColors.muted,
    };
    final amountColor = iconColor;
    final iconBg = switch (isCredit) {
      true => AppColors.goodSoft,
      false => AppColors.amberSoft,
      null => AppColors.surface3,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              switch (isCredit) {
                true => Icons.arrow_upward_rounded,
                false => Icons.arrow_downward_rounded,
                null => Icons.swap_vert_rounded,
              },
              size: 15,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: tsJakarta(11.5, FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 1),
                Text(date,
                    style: tsJakarta(9, FontWeight.w400,
                        color: AppColors.muted)),
              ],
            ),
          ),
          Text(
            amount,
            style: tsBricolage(12.5, FontWeight.w800,
                color: amountColor),
          ),
        ],
      ),
    );
  }
}

/// Container do extrato com linhas separadas.
class LedgerCard extends StatelessWidget {
  const LedgerCard({required this.rows, super.key});
  final List<LedgerRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(height: 1, color: AppColors.line),
          ],
        ],
      ),
    );
  }
}
