import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Os dois jeitos de levar os dados para fora do app.
enum FormatoExportacao { planilha, pdf }

/// Pergunta em que formato exportar: planilha (o CSV que já existia) ou PDF.
///
/// Os três pontos de exportação — extrato, relatórios e informe anual — usam
/// esta mesma escolha, com o mesmo texto, para que "Exportar" signifique a
/// mesma coisa em todo lugar. Devolve `null` se a pessoa desistir.
Future<FormatoExportacao?> escolherFormatoExportacao(BuildContext context) {
  return showModalBottomSheet<FormatoExportacao>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Exportar',
                style: tsBricolage(18, FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 10),
            _Opcao(
              key: const Key('exportar-planilha'),
              icone: Icons.table_chart_outlined,
              titulo: 'Planilha (Excel/CSV)',
              subtitulo: 'Copia os dados para colar no Excel ou no Google Planilhas.',
              onTap: () => Navigator.pop(ctx, FormatoExportacao.planilha),
            ),
            const SizedBox(height: 8),
            _Opcao(
              key: const Key('exportar-pdf'),
              icone: Icons.picture_as_pdf_outlined,
              titulo: 'PDF',
              subtitulo: 'Um arquivo pronto para imprimir, guardar ou enviar.',
              onTap: () => Navigator.pop(ctx, FormatoExportacao.pdf),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Opcao extends StatelessWidget {
  const _Opcao({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    super.key,
  });

  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icone, size: 22, color: AppColors.tealDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo,
                        style: tsJakarta(13, FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(subtitulo,
                        style: tsJakarta(11, FontWeight.w400, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
