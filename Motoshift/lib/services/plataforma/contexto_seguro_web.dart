import 'dart:js_interop';

@JS('window.isSecureContext')
external bool? get _isSecureContext;

@JS('window.location.origin')
external String? get _origem;

/// `window.isSecureContext`: HTTPS, ou `localhost`. É o que o navegador exige
/// para liberar `navigator.geolocation` — aberto por IP da rede (http://
/// 192.168.0.10:8080), o pedido de posição falha sem nem perguntar.
bool contextoSeguroDoNavegador() => _isSecureContext ?? true;

/// De onde a página foi aberta, para a mensagem dizer o que está errado.
String? enderecoDaPagina() => _origem;
