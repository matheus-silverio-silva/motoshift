import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Estrutura padrão de tela: gradiente teal no fundo → card surface2 com
/// cantos arredondados sobrepõe o cabeçalho, criando o efeito "lift".
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.header,
    required this.body,
    this.bottomNav,
    this.floatingActionButton,
    this.drawer,
    super.key,
  });

  final Widget header;
  final Widget body;
  final Widget? bottomNav;
  final Widget? floatingActionButton;

  /// Menu lateral. Quando informado, o [AppHeader] mostra sozinho o botão que
  /// o abre — as telas não precisam saber que ele existe.
  final Widget? drawer;

  /// Largura máxima do conteúdo. App é mobile-first: em telas largas (web/desktop)
  /// o conteúdo fica centralizado nesta largura em vez de esticar por toda a tela.
  static const double maxContentWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tealDeep,
      drawer: drawer,
      body: _centralizar(
        Column(
          children: [
            header,
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: ColoredBox(
                  color: AppColors.surface2,
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomNav == null
          ? null
          : Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxContentWidth),
                child: bottomNav,
              ),
            ),
      floatingActionButton: floatingActionButton,
    );
  }

  /// Restringe a largura e centraliza o filho quando a tela é maior que
  /// [maxContentWidth]. No mobile o filho ocupa 100% (comportamento original).
  Widget _centralizar(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}
