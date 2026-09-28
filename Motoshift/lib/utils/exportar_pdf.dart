import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../theme/app_theme.dart';

/// Entrega ao usuário o PDF gerado no app.
///
/// O mesmo caminho do "Baixar PDF" do documento fiscal: o pacote `printing`
/// abre a folha de compartilhar no celular e baixa o arquivo no navegador.
/// Falha vira aviso na tela, e não um toque que parece não ter feito nada.
Future<void> entregarPdf(BuildContext context, Uint8List bytes,
    {required String nomeDoArquivo}) async {
  try {
    await Printing.sharePdf(bytes: bytes, filename: nomeDoArquivo);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Não foi possível entregar o PDF: $e'),
      backgroundColor: AppColors.error,
    ));
  }
}
