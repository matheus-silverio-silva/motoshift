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
    super.key,
  });

  final Widget header;
  final Widget body;
  final Widget? bottomNav;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tealDeep,
      body: Column(
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
      bottomNavigationBar: bottomNav,
      floatingActionButton: floatingActionButton,
    );
  }
}
