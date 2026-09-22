import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Entrega ao usuário o CSV que o backend gerou.
///
/// <h3>Por que a área de transferência</h3>
/// O botão "Exportar CSV" existia desde o extrato e não exportava nada: ele
/// baixava o arquivo do servidor e mostrava "N lançamentos exportados" — o
/// conteúdo morria na memória do app. Gravar arquivo exigiria um pacote a
/// mais e permissão de armazenamento em três plataformas; a área de
/// transferência funciona em todas, inclusive no web, e cola direto numa
/// planilha. O aviso diz o que aconteceu e o que fazer com isso, em vez de
/// dizer "exportado" e sumir.
Future<void> entregarCsv(BuildContext context, String csv,
    {required String nomeSugerido}) async {
  final linhas = csv.trim().isEmpty ? 0 : csv.trim().split('\n').length - 1;
  await Clipboard.setData(ClipboardData(text: csv));
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(linhas <= 0
        ? 'Nada a exportar neste filtro.'
        : '$linhas linha(s) copiadas. Cole numa planilha e salve como '
            '"$nomeSugerido".'),
    backgroundColor: linhas <= 0 ? AppColors.muted : AppColors.good,
    duration: const Duration(seconds: 5),
  ));
}
