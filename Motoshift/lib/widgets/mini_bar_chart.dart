import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Gráfico de barras simples com rótulos de dias. Fiel ao .bars do protótipo.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    required this.values,
    required this.labels,
    this.highlightIndex,
    this.height = 62,
    super.key,
  });

  final List<double> values;
  final List<String> labels;

  /// Índice da barra destacada (gradiente teal). null = nenhuma destaque.
  final int? highlightIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxVal = values.fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: height + 18, // espaço para labels abaixo
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final ratio = maxVal > 0 ? values[i] / maxVal : 0.0;
          final isHot = i == (highlightIndex ?? _defaultHot());
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: LayoutBuilder(builder: (ctx, bc) {
                      final barH = (height * ratio).clamp(4.0, height);
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: barH,
                          decoration: BoxDecoration(
                            gradient: isHot
                                ? const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      AppColors.tealBright,
                                      AppColors.teal,
                                    ],
                                  )
                                : null,
                            color: isHot ? null : AppColors.tealSoft,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5)),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    i < labels.length ? labels[i] : '',
                    style: tsJakarta(7.5, FontWeight.w700,
                        color: AppColors.muted),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  int _defaultHot() {
    if (values.isEmpty) return 0;
    double max = values[0];
    int idx = 0;
    for (int i = 1; i < values.length; i++) {
      if (values[i] > max) {
        max = values[i];
        idx = i;
      }
    }
    return idx;
  }
}
