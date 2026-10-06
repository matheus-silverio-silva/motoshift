// Desenha o ícone do MotoShift — a FONTE dos ícones de todas as plataformas.
//
// Não havia arte: o app saía com o ícone padrão do Flutter. Este arquivo
// desenha um ícone simples e original com as cores do tema
// (lib/theme/app_theme.dart) e a fonte da marca (Bricolage Grotesque
// ExtraBold, em assets/fonts): o monograma "MS" sobre o gradiente verde-água
// do botão principal, com um traço âmbar — o acento do app.
//
// É um teste só para ter o motor de desenho do Flutter à mão (Canvas, fonte,
// PNG) sem depender de ferramenta externa. Fica em tool/, fora de test/, para
// não rodar na suíte nem no CI. Para redesenhar e regerar os ícones:
//
//   flutter test tool/gerar_icone_test.dart
//   dart run flutter_launcher_icons
//
// Saída:
//   assets/icon/icon.png             1024×1024, fundo cheio (iOS, web, Android legado)
//   assets/icon/icon_foreground.png  1024×1024, só a marca sobre transparente — o
//                                    primeiro plano do ícone adaptativo do Android
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/theme/app_theme.dart';

const double _lado = 1024;
const String _familia = 'IconeBricolage';

void main() {
  testWidgets('gera assets/icon/icon.png e icon_foreground.png', (tester) async {
    // Ler arquivo, carregar fonte e codificar PNG são E/S de verdade: fora do
    // relógio falso do teste.
    await tester.runAsync(() async {
      final bytes =
          await File('assets/fonts/BricolageGrotesque-ExtraBold.ttf').readAsBytes();
      await (FontLoader(_familia)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();

      await _salvar('assets/icon/icon.png', _desenhar(comFundo: true));
      // A mesma marca, sem o fundo. O Android recorta o ícone adaptativo e só
      // garante o miolo (uns 66%); quem a põe na zona segura é o
      // flutter_launcher_icons, que embrulha o primeiro plano num inset de 16%
      // — encolher aqui também deixaria a marca pequena demais.
      await _salvar('assets/icon/icon_foreground.png', _desenhar(comFundo: false));
    });
  });
}

ui.Picture _desenhar({required bool comFundo}) {
  const escala = 1.0;
  final gravador = ui.PictureRecorder();
  final canvas = Canvas(gravador, const Rect.fromLTWH(0, 0, _lado, _lado));

  if (comFundo) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _lado, _lado),
      Paint()
        ..shader = AppColors.primaryGradient
            .createShader(const Rect.fromLTWH(0, 0, _lado, _lado)),
    );
  }

  final letras = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: 'MS',
      style: TextStyle(
        fontFamily: _familia,
        fontWeight: FontWeight.w800,
        fontSize: 470 * escala,
        height: 1.0,
        letterSpacing: -14 * escala,
        color: Colors.white,
      ),
    ),
  )..layout();

  // O conjunto (letras + traço) centrado no quadro.
  final alturaDoTraco = 44 * escala;
  // Negativo: a caixa do texto inclui o espaço das descendentes, que "MS" não
  // usa — sem isso o traço fica longe das letras.
  final respiro = -58 * escala;
  final alturaTotal = letras.height + respiro + alturaDoTraco;
  final topo = (_lado - alturaTotal) / 2;
  final esquerda = (_lado - letras.width) / 2;
  letras.paint(canvas, Offset(esquerda, topo));

  // O traço âmbar sob as letras: a hora marcada do turno.
  final larguraDoTraco = letras.width * 0.46;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(
          esquerda + 6 * escala, topo + letras.height + respiro, larguraDoTraco, alturaDoTraco),
      Radius.circular(alturaDoTraco / 2),
    ),
    Paint()..color = AppColors.amber,
  );

  return gravador.endRecording();
}

Future<void> _salvar(String caminho, ui.Picture desenho) async {
  final imagem = await desenho.toImage(_lado.toInt(), _lado.toInt());
  final png = await imagem.toByteData(format: ui.ImageByteFormat.png);
  final arquivo = File(caminho);
  await arquivo.parent.create(recursive: true);
  await arquivo.writeAsBytes(png!.buffer.asUint8List());
}
