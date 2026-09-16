/// Duas primeiras letras do primeiro nome ("Cláudia Oliveira" → "CL").
///
/// Vive aqui porque tem três donos: o avatar da topbar do desktop, o bloco do
/// usuário na barra lateral e o header do celular. Estava copiada em dois
/// deles, e a gaveta do celular seria a terceira cópia.
String iniciaisDe(String? nome) {
  final primeiro = (nome ?? '').trim().split(RegExp(r'\s+')).first;
  if (primeiro.isEmpty) return '·';
  return primeiro.length >= 2
      ? primeiro.substring(0, 2).toUpperCase()
      : primeiro.toUpperCase();
}
