import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// O olho que mostra e esconde a senha, no fim do campo.
///
/// Era um `GestureDetector` em volta de um ícone, repetido em cada tela: para
/// o leitor de tela, um "botão" sem nome. Aqui ele diz o que FAZ — e o rótulo
/// muda junto com o estado, porque "Mostrar senha" com a senha já à mostra
/// seria mentira.
///
/// O desenho é o mesmo de antes (ícone de 16). O que cresce é só a área que
/// responde ao toque, para os lados: a altura não pode passar da linha do
/// campo sem empurrar a caixa inteira.
class OlhoDaSenha extends StatelessWidget {
  const OlhoDaSenha({required this.visivel, required this.onTap, super.key});

  /// `true` quando a senha está à mostra.
  final bool visivel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // `container`: um nó só dele. Sem isso o toque se fundia ao nó do campo
    // de texto, e o botão deixava de existir para o leitor de tela.
    return Semantics(
      container: true,
      button: true,
      label: visivel ? 'Ocultar senha' : 'Mostrar senha',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 32,
          height: 16,
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(
              visivel
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 16,
              color: AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
