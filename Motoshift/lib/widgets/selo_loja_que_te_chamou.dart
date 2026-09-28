import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Loja que já te chamou": o turno é de uma loja que tem este entregador
/// entre os favoritos (V18). É o único rastro do favorito que o entregador vê —
/// a lista de favoritos é da loja.
class SeloLojaQueTeChamou extends StatelessWidget {
  const SeloLojaQueTeChamou({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('selo-loja-que-te-chamou'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_rounded,
              size: 11, color: AppColors.onTertiaryContainer),
          const SizedBox(width: 4),
          Text('Loja que já te chamou',
              style: tsJakarta(10, FontWeight.w700,
                  color: AppColors.onTertiaryContainer)),
        ],
      ),
    );
  }
}
