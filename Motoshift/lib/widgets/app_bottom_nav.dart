import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/nav_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Barra de navegação inferior com os quatro atalhos do papel logado.
///
/// <h3>O que mudou, e por quê</h3>
/// Esta barra recebia `userType`, `currentIndex` e `onTap` de **cada tela**, e
/// sete telas carregavam o mesmo `switch (i)` copiado à mão. Três coisas ruins
/// saíam disso:
///
/// * a Agenda passava `UserType.lojista` fixo, então o entregador via a barra
///   do lojista e "Início" o levava para um dashboard que o AuthGuard recusava;
/// * acrescentar um item exigia editar sete `switch`, e bastava esquecer um
///   para a barra ficar diferente dependendo da tela;
/// * o índice destacado era um número escrito à mão, que ninguém atualizava
///   quando a ordem dos itens mudava.
///
/// Agora a barra descobre sozinha o papel (pelo [AuthService]) e os itens (pelo
/// [NavConfig]); a tela informa apenas **em que seção está**, e o destaque sai
/// da comparação de rotas.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({required this.rotaAtual, super.key});

  /// A seção em que a tela está — o item correspondente fica destacado.
  final String rotaAtual;

  @override
  Widget build(BuildContext context) {
    final papel = context.watch<AuthService>().usuario?.tipo;
    if (papel == null) return const SizedBox.shrink();

    final itens = NavConfig.barraInferior(papel);
    final secao = NavConfig.secaoDe(rotaAtual, papel: papel);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line, width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final item in itens)
                Expanded(
                  child: _NavTap(
                    item: item,
                    selected: item.route == secao,
                    // Item da barra é troca de seção: substitui a pilha.
                    onTap: () => NavConfig.irParaSecao(context, item.route),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTap extends StatelessWidget {
  const _NavTap({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.teal : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 19, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: tsJakarta(8, FontWeight.w700, color: color),
            ),
            const SizedBox(height: 2),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.teal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// O enum `UserType` que vivia aqui foi removido. Ele duplicava [TipoUsuario] e
// existia só para a tela dizer à barra qual papel desenhar — o que nunca
// deveria ter sido decisão da tela, e a Agenda provou isso passando
// `UserType.lojista` fixo para os dois papéis.
