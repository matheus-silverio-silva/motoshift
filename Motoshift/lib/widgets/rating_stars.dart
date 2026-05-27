import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < rating;
            return GestureDetector(
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
            );
          }),
        ),
        if (rating > 0) ...[
          const SizedBox(height: 6),
          Text(
            _labels[rating] ?? '',
            style: tsJakarta(11, FontWeight.w700,
                color: AppColors.tealDeep),
          ),
        ],
      ],
    );
  }
}
