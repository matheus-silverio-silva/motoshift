
import 'package:flutter/foundation.dart';

import 'plataforma/entrega_de_arquivo.dart' as plataforma;

/// Um arquivo pronto para a pessoa guardar: os bytes, o nome e o tipo.
@immutable
class ArquivoBaixado {
  const ArquivoBaixado(this.bytes, this.nome, this.mime);

  final Uint8List bytes;
  final String nome;
  final String mime;
}

/// Quem entrega o arquivo. No web, um download de verdade (Blob e âncora); no
/// celular e no desktop, a folha de compartilhar do sistema — de onde a pessoa
/// salva em Arquivos, manda por e-mail ou abre na planilha.
///
/// Trocável nos testes pelo mesmo motivo do `fingirImpressora`: o caminho de
/// verdade passa por canal de plataforma, que num teste não existe.
typedef EntregaDeArquivo = Future<void> Function(ArquivoBaixado arquivo);

EntregaDeArquivo _entrega =
    (a) => plataforma.entregar(a.bytes, a.nome, a.mime);

/// Só os testes chamam: troca a entrega e devolve a anterior.
@visibleForTesting
EntregaDeArquivo trocarEntregaDeArquivo(EntregaDeArquivo nova) {
  final anterior = _entrega;
  _entrega = nova;
  return anterior;
}

/// O "baixar arquivo" do app, num lugar só: a planilha (CSV) e o calendário
/// (.ics) passam por aqui. O PDF continua no `printing`, que já baixa no web e
/// abre a folha de compartilhar no celular — e sabe imprimir, que isto não faz.
Future<void> baixarArquivo(Uint8List bytes, String nome, String mime) =>
    _entrega(ArquivoBaixado(bytes, nome, mime));
