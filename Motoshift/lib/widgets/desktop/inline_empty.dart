import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Estado vazio compacto para usar dentro de um card do desktop, onde o
/// `EmptyState` cheio — que já traz moldura e sombra próprias — ficaria
/// aninhado num card com a mesma moldura.
class InlineEmpty extends StatelessWidget {
  const InlineEmpty({
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppColors.tealDeep),
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: tsBricolage(14, FontWeight.w800, color: AppColors.ink),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: tsJakarta(12, FontWeight.w400, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
