import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Celular e desktop: a folha de compartilhar do sistema. É dela que a pessoa
/// salva em Arquivos, manda por e-mail ou abre direto na planilha — gravar
/// numa pasta escolhida pelo app exigiria permissão de armazenamento em cada
/// plataforma.
Future<void> entregar(Uint8List bytes, String nome, String mime) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: mime, name: nome)],
    fileNameOverrides: [nome],
    subject: nome,
  ));
}
