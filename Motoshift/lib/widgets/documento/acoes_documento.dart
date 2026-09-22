import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../models/documento_fiscal.dart';
import '../../services/documento_pdf.dart';
import '../../theme/app_theme.dart';

/// "Baixar PDF" e "Imprimir" de um documento fiscal.
///
/// Os dois usam o pacote `printing`, que no Flutter web baixa o arquivo e abre
/// o diálogo de impressão do navegador; no celular, a folha de compartilhar e
/// o serviço de impressão do sistema. O PDF é gerado uma vez por toque — o
/// documento não muda, então não há o que invalidar.
class AcoesDocumento extends StatefulWidget {
  const AcoesDocumento({required this.documento, super.key});

  final DocumentoFiscal documento;

  @override
  State<AcoesDocumento> createState() => _AcoesDocumentoState();
}

class _AcoesDocumentoState extends State<AcoesDocumento> {
  bool _ocupado = false;

  Future<void> _baixar() => _comPdf((bytes) => Printing.sharePdf(
        bytes: bytes,
        filename: DocumentoPdf.nomeDoArquivo(widget.documento),
      ));

  Future<void> _imprimir() => _comPdf((bytes) => Printing.layoutPdf(
        name: DocumentoPdf.nomeDoArquivo(widget.documento),
        onLayout: (_) async => bytes,
      ));

  Future<void> _comPdf(Future<Object?> Function(Uint8List bytes) acao) async {
    setState(() => _ocupado = true);
    try {
      final bytes = await DocumentoPdf.gerar(widget.documento);
      await acao(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não foi possível gerar o PDF: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('documento-baixar-pdf'),
            onPressed: _ocupado ? null : _baixar,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Baixar PDF',
                style: tsJakarta(12.5, FontWeight.w700, color: Colors.white)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.teal,
              minimumSize: const Size(0, 46),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('documento-imprimir'),
            onPressed: _ocupado ? null : _imprimir,
            icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.tealDeep),
            label: Text('Imprimir',
                style: tsJakarta(12.5, FontWeight.w700, color: AppColors.tealDeep)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              side: const BorderSide(color: AppColors.teal, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
