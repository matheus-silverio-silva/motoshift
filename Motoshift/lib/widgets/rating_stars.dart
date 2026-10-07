import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/resumo_acessivel.dart';

/// Estrelas de avaliação interativas (1–5). Fiel ao .stars do protótipo.
class RatingStars extends StatelessWidget {
  const RatingStars({
    required this.rating,
    this.onRatingChanged,
    this.size = 28,
    super.key,
  });

  final int rating;
  final ValueChanged<int>? onRatingChanged;
  final double size;

  static const _labels = {
    1: 'Ruim · 1 de 5',
    2: 'Regular · 2 de 5',
    3: 'Ok · 3 de 5',
    4: 'Muito bom · 4 de 5',
    5: 'Excelente · 5 de 5',
  };

  @override
  Widget build(BuildContext context) {
    // Duas leituras, conforme o uso:
    //
    //  - só exibição: um nó único, "Nota 4 de 5". Cinco ícones mudos não
    //    dizem nota nenhuma;
    //  - para dar a nota: cada estrela é um botão com nome ("3 estrelas") e
    //    diz se é a escolhida. O texto de baixo ("Ok · 3 de 5") continua na
    //    árvore e é anunciado quando muda.
    final somenteLeitura = onRatingChanged == null;

    return Semantics(
      container: true,
      explicitChildNodes: !somenteLeitura,
      label: somenteLeitura ? resumoDaNota(rating) : null,
      excludeSemantics: somenteLeitura,
      child: _buildEstrelas(),
    );
  }

  Widget _buildEstrelas() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < rating;
            return Semantics(
              container: true,
              button: onRatingChanged != null,
              selected: i + 1 == rating,
              label: i == 0 ? '1 estrela' : '${i + 1} estrelas',
              child: GestureDetector(
                onTap: onRatingChanged != null
                    ? () => onRatingChanged!(i + 1)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size,
                    color: filled ? AppColors.amber : AppColors.line,
                  ),
                ),
              ),
            );
          }),
        ),
        if (rating > 0) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _labels[rating] ?? '',
              style: tsJakarta(11, FontWeight.w700,
                  color: AppColors.tealDeep),
            ),
          ),
        ],
      ],
    );
  }
}
