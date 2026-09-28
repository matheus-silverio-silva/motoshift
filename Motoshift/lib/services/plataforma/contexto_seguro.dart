// A pergunta "o navegador considera esta página segura?" só existe no web.
// Fora dele a resposta é sempre sim: o GPS do aparelho não depende de HTTPS.
export 'contexto_seguro_io.dart'
    if (dart.library.js_interop) 'contexto_seguro_web.dart';
