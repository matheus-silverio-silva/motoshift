import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Estado vazio padrão — ícone em destaque, título e subtítulo.
/// Substitui os textos "secos" por um bloco visual mais convidativo e
/// consistente em toda a aplicação.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.titulo,
    this.subtitulo,
    super.key,
  });

  final IconData icon;
  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 26, color: AppColors.tealDeep),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: tsBricolage(15, FontWeight.w800, color: AppColors.ink),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
