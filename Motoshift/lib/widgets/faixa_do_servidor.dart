import 'package:flutter/material.dart';

import '../services/servidor_service.dart';
import '../theme/app_theme.dart';

/// A faixa que avisa que o backend está acordando (SCRUM-48).
///
/// Não ocupa espaço enquanto o servidor responde no tempo normal. Passados os
/// primeiros segundos sem resposta, diz o que está acontecendo — no plano
/// gratuito o servidor dorme e leva minutos para voltar —; passado o limite,
/// troca para o erro com "Tentar novamente".
///
/// O aviso é texto com ícone, não só cor, e é uma região viva: o leitor de
/// tela o anuncia quando aparece.
class FaixaDoServidor extends StatelessWidget {
  const FaixaDoServidor({
    required this.servidor,
    required this.aoTentarDeNovo,
    super.key,
  });

  final ServidorService servidor;

  /// O que o "Tentar novamente" faz — cada tela repete a espera que era dela.
  final VoidCallback aoTentarDeNovo;

  static const String textoAcordando =
      'Acordando o servidor… no plano gratuito isso leva até 3 minutos';
  static const String textoSemResposta =
      'O servidor não respondeu. Confira a internet e tente de novo.';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: servidor,
      builder: (context, _) => switch (servidor.estado) {
        EstadoDoServidor.acordando => const _Faixa(
            key: Key('servidor-acordando'),
            texto: textoAcordando,
            fundo: AppColors.amberSoft,
            borda: AppColors.amber,
            indicador: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onTertiaryContainer,
              ),
            ),
          ),
        EstadoDoServidor.semResposta => _Faixa(
            key: const Key('servidor-sem-resposta'),
            texto: textoSemResposta,
            fundo: AppColors.errorContainer,
            borda: AppColors.error,
            indicador: const Icon(Icons.cloud_off_rounded,
                size: 18, color: AppColors.onErrorContainer),
            acao: TextButton(
              key: const Key('servidor-tentar-novamente'),
              onPressed: aoTentarDeNovo,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onErrorContainer,
                minimumSize: const Size(48, 48),
                textStyle: tsJakarta(13, FontWeight.w800),
              ),
              child: const Text('Tentar novamente'),
            ),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({
    required this.texto,
    required this.fundo,
    required this.borda,
    required this.indicador,
    this.acao,
    super.key,
  });

  final String texto;
  final Color fundo;
  final Color borda;
  final Widget indicador;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: fundo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borda, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: ExcludeSemantics(child: indicador),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      texto,
                      style: tsJakarta(12.5, FontWeight.w700,
                          color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (acao != null)
              Align(alignment: Alignment.centerRight, child: acao!),
          ],
        ),
      ),
    );
  }
}
