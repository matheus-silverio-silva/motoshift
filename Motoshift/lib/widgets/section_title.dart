import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Título de seção com link opcional "ver mais". Fiel ao .sec-title do protótipo.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Com link, o padding vertical encolhe porque o alvo de 44px já ocupa
      // esse espaço: o que era margem virou área de toque, e a distância
      // visual entre o título e a lista continua a mesma. Sem link, nada
      // muda — a maioria dos usos não tem ação.
      padding: action == null
          ? const EdgeInsets.fromLTRB(2, 14, 2, 9)
          : const EdgeInsets.fromLTRB(2, 1, 2, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: tsBricolage(13, FontWeight.w800, color: AppColors.ink)),
          if (action != null)
            // O link tinha 14px de altura de toque — um alvo que só acerta
            // quem mira bem. O texto continua do mesmo tamanho; quem cresceu
            // foi a caixa que recebe o toque.
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    action!,
                    style: tsJakarta(10, FontWeight.w700,
                        color: AppColors.teal),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
