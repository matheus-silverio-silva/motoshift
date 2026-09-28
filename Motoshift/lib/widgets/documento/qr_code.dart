import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// Um QR Code desenhado na tela, sem imagem nem rede.
///
/// O pacote `barcode` (o mesmo que o PDF usa) devolve os módulos do código
/// como retângulos, e o pintor só os preenche: a tela e o PDF desenham o mesmo
/// QR Code a partir do mesmo conteúdo.
class QrCode extends StatelessWidget {
  const QrCode({required this.conteudo, this.tamanho = 96, super.key});

  final String conteudo;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanho,
      height: tamanho,
      color: Colors.white,
      child: CustomPaint(painter: _PintorQr(conteudo)),
    );
  }
}

class _PintorQr extends CustomPainter {
  _PintorQr(this.conteudo);

  final String conteudo;

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()..color = Colors.black;
    for (final e in Barcode.qrCode()
        .make(conteudo, width: size.width, height: size.height)) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), tinta);
      }
    }
  }

  @override
  bool shouldRepaint(_PintorQr antigo) => antigo.conteudo != conteudo;
}
