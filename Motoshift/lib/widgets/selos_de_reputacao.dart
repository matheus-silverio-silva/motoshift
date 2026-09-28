import 'package:flutter/material.dart';

import '../models/selo.dart';
import '../theme/app_theme.dart';

/// Os selos de reputação como chips; tocar um mostra o critério.
///
/// Some quando não há selo — um "nenhum selo" no perfil de quem acabou de
/// chegar soaria como demérito.
class SelosDeReputacao extends StatelessWidget {
  const SelosDeReputacao({required this.selos, this.centralizar = false, super.key});

  final List<Selo> selos;
  final bool centralizar;

  static IconData _icone(String codigo) => switch (codigo) {
        'turnos_concluidos' => Icons.workspace_premium_outlined,
        'sem_cancelar' => Icons.event_available_outlined,
        'nota_alta' => Icons.star_rounded,
        'pontual' => Icons.timer_outlined,
        'paga_gorjeta' => Icons.volunteer_activism_outlined,
        'toda_semana' => Icons.date_range_outlined,
        _ => Icons.verified_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (selos.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const Key('selos-de-reputacao'),
      alignment: centralizar ? WrapAlignment.center : WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in selos)
          Semantics(
            button: true,
            label: '${s.titulo}. Toque para ver o critério.',
            child: InkWell(
              key: Key('selo-${s.codigo}'),
              borderRadius: BorderRadius.circular(999),
              onTap: () => _mostrarCriterio(context, s),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.amberSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icone(s.codigo),
                        size: 15, color: AppColors.onTertiaryContainer),
                    const SizedBox(width: 6),
                    Text(s.titulo,
                        style: tsJakarta(11.5, FontWeight.w700,
                            color: AppColors.onTertiaryContainer)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _mostrarCriterio(BuildContext context, Selo s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(_icone(s.codigo), color: AppColors.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.titulo,
                  style: tsBricolage(16, FontWeight.w800, color: AppColors.ink)),
            ),
          ],
        ),
        content: Text(s.criterio,
            key: const Key('selo-criterio'),
            style: tsJakarta(12.5, FontWeight.w500,
                color: AppColors.text, height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Entendi')),
        ],
      ),
    );
  }
}
