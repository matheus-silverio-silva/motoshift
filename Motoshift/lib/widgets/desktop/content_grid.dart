import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Área de conteúdo desktop: max-width 1280 centralizado, padding 24 e grid de
/// 12 colunas com gap 24, conforme o canvas.
///
/// Os filhos normalmente são [GridCol]; um filho que não seja [GridCol] ocupa
/// as 12 colunas (linha inteira).
///
/// Com um único filho que não some 12 colunas, o [Wrap] encolhe até a largura
/// dele e o [Align] o centraliza — é o que acontece na tela de estabelecimento
/// do lojista, que tem uma coluna só. O efeito é desejável (formulário curto
/// centrado em vez de encostado à esquerda), mas não é óbvio olhando o código,
/// daí a nota.
class ContentGrid extends StatelessWidget {
  const ContentGrid({
    required this.children,
    this.scrollable = true,
    super.key,
  });

  static const double maxWidth = 1280;
  static const double gap = 24;
  static const double padding = 24;
  static const int columns = 12;

  final List<Widget> children;

  /// `false` para telas que gerenciam a própria rolagem (ex.: master-detail
  /// com painéis de altura cheia).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final grid = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final unit =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final child in children)
                  SizedBox(
                    // -0.1 evita quebra de linha por erro de ponto flutuante.
                    width: math.max(
                        0, unit * _spanOf(child) + gap * (_spanOf(child) - 1) - 0.1),
                    child: child,
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (!scrollable) {
      return Padding(padding: const EdgeInsets.all(padding), child: grid);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(padding),
      child: grid,
    );
  }

  int _spanOf(Widget child) {
    final span = child is GridCol ? child.span : columns;
    return span.clamp(1, columns);
  }
}

/// Define quantas das 12 colunas o filho ocupa dentro de um [ContentGrid].
class GridCol extends StatelessWidget {
  const GridCol({required this.span, required this.child, super.key});

  final int span;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
