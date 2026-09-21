import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Estado vazio padrão — ícone em destaque, título, subtítulo e **uma saída**.
///
/// Substitui os textos "secos" por um bloco visual consistente em toda a
/// aplicação.
///
/// <h3>Por que a ação</h3>
/// Um estado vazio sem ação deixa a pessoa parada: ela leu que não há nada e
/// continua na mesma tela, sem saber se recarrega, se volta, ou se o problema
/// foi dela. Era o caso do detalhe do turno aberto sem argumento, que mostrava
/// um `Text('Turno não encontrado.')` no meio da tela e nada mais. [acaoLabel]
/// é opcional porque "nenhum turno nesse filtro" já tem a saída ao lado (os
/// próprios filtros) — mas quando não houver saída visível, ela vem aqui.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.titulo,
    this.subtitulo,
    this.acaoLabel,
    this.onAcao,
    super.key,
  });

  final IconData icon;
  final String titulo;
  final String? subtitulo;

  /// Texto do botão de saída — "Tentar novamente", "Voltar", "Ver turnos".
  final String? acaoLabel;
  final VoidCallback? onAcao;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 26, color: AppColors.tealDeep),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: tsBricolage(15, FontWeight.w800, color: AppColors.ink),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
            ),
          ],
          if (acaoLabel != null && onAcao != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('empty-state-acao'),
              onPressed: onAcao,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.teal,
                minimumSize: const Size(0, 44),
              ),
              child: Text(acaoLabel!,
                  style: tsJakarta(12.5, FontWeight.w700, color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}
