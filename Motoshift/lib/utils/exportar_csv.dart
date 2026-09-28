import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'baixar_arquivo.dart';

/// A marca de ordem de bytes do UTF-8. Sem ela, o Excel em português abre o
/// CSV como Windows-1252 e "Farmácia" vira "FarmÃ¡cia".
const List<int> bomUtf8 = [0xEF, 0xBB, 0xBF];

/// O CSV como arquivo: UTF-8 com BOM.
Uint8List csvComBom(String csv) =>
    Uint8List.fromList([...bomUtf8, ...utf8.encode(csv)]);

/// Entrega ao usuário o CSV que o backend gerou — a opção "Planilha" do
/// botão Exportar (a outra, PDF, é `entregarPdf`).
///
/// <h3>Um arquivo, e não a área de transferência</h3>
/// Até aqui o CSV ia para a área de transferência, com o aviso de colar numa
/// planilha: funcionava em toda plataforma, mas não era um arquivo. Agora é:
/// no web o navegador baixa `extrato.csv`; no celular abre a folha de
/// compartilhar, de onde a pessoa salva ou abre na planilha. Ver
/// [baixarArquivo].
Future<void> entregarCsv(BuildContext context, String csv,
    {required String nomeSugerido}) async {
  final linhas = csv.trim().isEmpty ? 0 : csv.trim().split('\n').length - 1;
  final messenger = ScaffoldMessenger.of(context);

  if (linhas <= 0) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Nada a exportar neste filtro.'),
      backgroundColor: AppColors.muted,
    ));
    return;
  }

  try {
    await baixarArquivo(csvComBom(csv), nomeSugerido, 'text/csv;charset=utf-8');
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('Não foi possível baixar a planilha: $e'),
      backgroundColor: AppColors.error,
    ));
    return;
  }

  messenger.showSnackBar(SnackBar(
    content: Text('Planilha "$nomeSugerido" pronta — $linhas '
        '${linhas == 1 ? 'linha' : 'linhas'}.'),
    backgroundColor: AppColors.good,
    duration: const Duration(seconds: 5),
  ));
}
