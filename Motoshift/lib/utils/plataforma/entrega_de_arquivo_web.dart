import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> partes, _OpcoesDoBlob opcoes);
}

extension type _OpcoesDoBlob._(JSObject _) implements JSObject {
  external factory _OpcoesDoBlob({String type});
}

extension type _Ancora._(JSObject _) implements JSObject {
  external set href(String valor);
  external set download(String valor);
  external void click();
  external void remove();
}

@JS('URL.createObjectURL')
external String _urlDoBlob(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revogarUrl(String url);

@JS('document.createElement')
external _Ancora _criarAncora(String tag);

@JS('document.body.appendChild')
external void _anexarAoCorpo(JSObject elemento);

/// Web: um download de verdade, com o nome certo — o mesmo mecanismo que o
/// `printing` usa para o PDF, aqui para qualquer tipo (CSV, calendário). Sem
/// pacote: só `dart:js_interop`, do próprio SDK.
Future<void> entregar(Uint8List bytes, String nome, String mime) async {
  final blob = _Blob([bytes.toJS].toJS, _OpcoesDoBlob(type: mime));
  final url = _urlDoBlob(blob);
  final ancora = _criarAncora('a')
    ..href = url
    ..download = nome;
  _anexarAoCorpo(ancora);
  ancora.click();
  ancora.remove();
  // O clique só agenda o download; soltar a URL na hora pode fazer o
  // navegador perder o arquivo antes de gravá-lo.
  Future<void>.delayed(const Duration(seconds: 5), () => _revogarUrl(url));
}
