import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

/// Card de turno na lista — ícone, nome, metadados, valor e pill de status.
/// Fiel ao .shift do protótipo.
class ShiftCard extends StatelessWidget {
  const ShiftCard({
    required this.name,
    required this.meta,
    required this.value,
    this.horario,
    this.iconData = Icons.schedule_outlined,
    this.amberIcon = false,
    this.pillLabel,
    this.pillVariant = PillVariant.ghost,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String name;

  /// Itens de metadados separados por " • " (ex: ['18:00–23:00', '4 km', '★ 4.9'])
  final List<String> meta;
  final String value;

  /// Quando informado, o card usa a hierarquia do protótipo v2: horário e
  /// valor na primeira linha, título e região na segunda. Sem ele o card
  /// mantém o formato antigo (título em cima), para não quebrar chamadas que
  /// ainda não migraram.
  final String? horario;
  final IconData iconData;
  final bool amberIcon;
  final String? pillLabel;
  final PillVariant pillVariant;

  /// Widget opcional no lugar da pill (ex: botão "Aceitar")
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (horario != null) return _buildHierarquiaNova();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1.5),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ícone
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    amberIcon ? AppColors.amberSoft : AppColors.tealSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                iconData,
                size: 18,
                color: amberIcon
                    ? AppColors.onTertiaryContainer
                    : AppColors.tealDeep,
              ),
            ),
            const SizedBox(width: 10),
            // nome + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: tsJakarta(12.5, FontWeight.w700,
                        color: AppColors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.join(' • '),
                    style: tsJakarta(10, FontWeight.w400,
                        color: AppColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // valor + pill
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: tsBricolage(13, FontWeight.w800,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                if (trailing != null)
                  trailing!
                else if (pillLabel != null)
                  StatusPill(label: pillLabel!, variant: pillVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hierarquia do protótipo v2 — o que o entregador procura primeiro é
  /// quando e quanto, não o nome do turno.
  Widget _buildHierarquiaNova() {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1.5),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: amberIcon ? AppColors.amberSoft : AppColors.tealSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                iconData,
                size: 20,
                color: amberIcon
                    ? AppColors.onTertiaryContainer
                    : AppColors.tealDeep,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          horario!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(13, FontWeight.w700,
                              color: AppColors.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        value,
                        style: tsBricolage(15, FontWeight.w800,
                            color: AppColors.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [name, ...meta].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(11, FontWeight.w400,
                              color: AppColors.muted),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ] else if (pillLabel != null) ...[
                        const SizedBox(width: 8),
                        StatusPill(label: pillLabel!, variant: pillVariant),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
