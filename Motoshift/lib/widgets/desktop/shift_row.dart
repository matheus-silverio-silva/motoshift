import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../status_pill.dart';

/// Linha de turno das listas do desktop.
///
/// A hierarquia é a do protótipo v2: horário e valor na primeira linha,
/// título/região e status na segunda — o oposto do ShiftCard do mobile, que
/// o refinamento da Fase 5 vai alinhar a esta.
class ShiftRow extends StatefulWidget {
  const ShiftRow({
    required this.horario,
    required this.valor,
    required this.meta,
    this.icon = Icons.storefront_outlined,
    this.amberIcon = false,
    this.pillLabel,
    this.pillVariant = PillVariant.ghost,
    this.selected = false,
    this.onTap,
    super.key,
  });

  /// Primeira linha, à esquerda (ex.: "18:00 - 23:00", "Amanhã, 17:30").
  final String horario;

  /// Primeira linha, à direita (ex.: "R$ 130").
  final String valor;

  /// Segunda linha, à esquerda (ex.: "Jantar · Batel · 2 vagas").
  final String meta;

  final IconData icon;
  final bool amberIcon;
  final String? pillLabel;
  final PillVariant pillVariant;

  /// Item ativo do master-detail: fundo teal claro e borda destacada.
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<ShiftRow> createState() => _ShiftRowState();
}

class _ShiftRowState extends State<ShiftRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.tealSoft
                : (_hover ? AppColors.surface2 : AppColors.surface),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected || _hover
                  ? AppColors.tealBright
                  : AppColors.line,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  // Sobre o fundo teal do item ativo o quadro do ícone vira
                  // branco, senão o ícone some no próprio fundo.
                  color: widget.selected
                      ? AppColors.surface
                      : (widget.amberIcon
                          ? AppColors.amberSoft
                          : AppColors.tealSoft),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: widget.amberIcon
                      ? const Color(0xFF9A6206)
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
                            widget.horario,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tsJakarta(13.5, FontWeight.w700,
                                color: AppColors.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.valor,
                          style: tsBricolage(16, FontWeight.w800,
                              color: AppColors.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tsJakarta(11.5, FontWeight.w400,
                                color: widget.selected
                                    ? AppColors.tealDeep
                                    : AppColors.muted),
                          ),
                        ),
                        if (widget.pillLabel != null) ...[
                          const SizedBox(width: 8),
                          StatusPill(
                            label: widget.pillLabel!,
                            variant: widget.pillVariant,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
