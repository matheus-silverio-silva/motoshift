import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/documento_fiscal.dart';
import '../../theme/app_theme.dart';

/// A faixa que diz, antes de qualquer outra coisa, que o documento é simulado.
///
/// Vai no topo de toda NFS-e e todo comprovante, na tela e no PDF. Um
/// documento com cara de nota fiscal circula — é baixado, impresso,
/// encaminhado —, e a frase precisa ir junto, não ficar numa tela anterior.
class MarcaSimulacao extends StatelessWidget {
  const MarcaSimulacao({this.texto = DocumentoFiscal.marcaPadrao, super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('marca-simulacao'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: tsJakarta(11, FontWeight.w800,
                      color: AppColors.onTertiaryContainer)
                  .copyWith(letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// A mesma frase em diagonal, por cima do documento inteiro.
///
/// A faixa do topo some quando a pessoa rola a tela ou recorta um trecho; a
/// marca d'água não. Fica translúcida e não recebe toque, para não atrapalhar
/// a leitura nem os botões.
class MarcaDagua extends StatelessWidget {
  const MarcaDagua({required this.child, this.texto = DocumentoFiscal.marcaPadrao, super.key});

  final Widget child;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: Center(
                child: Transform.rotate(
                  angle: -math.pi / 7,
                  child: Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: tsBricolage(22, FontWeight.w800,
                        color: AppColors.error.withOpacity(0.10)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
