import 'dart:convert';
import 'dart:typed_data';

/// O texto de um PDF gerado com `comprimir: false`, para o teste procurar
/// valores nele.
///
/// Com fonte TTF o pacote `pdf` não escreve letras: escreve o índice de cada
/// caractere na tabela da fonte (`[<0003001A…>]TJ`), e cada fonte embutida
/// traz a própria tabela de volta para Unicode (`beginbfchar … endbfchar`).
/// Aqui cada trecho é traduzido por cada tabela, e o resultado de cada uma
/// vira uma linha — a tabela certa produz o texto, as outras produzem ruído
/// que nenhuma busca de verdade casa. As palavras saem na ordem em que a
/// página as desenha, separadas por espaço.
String textoDoPdf(Uint8List bytes) {
  final bruto = latin1.decode(bytes, allowInvalid: true);

  final tabelas = <Map<int, int>>[];
  for (final m in RegExp(r'beginbfchar\n([\s\S]*?)endbfchar').allMatches(bruto)) {
    final tabela = <int, int>{};
    for (final par in RegExp(r'<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]{4})>').allMatches(m[1]!)) {
      tabela[int.parse(par[1]!, radix: 16)] = int.parse(par[2]!, radix: 16);
    }
    tabelas.add(tabela);
  }

  final trechos = [
    for (final m in RegExp(r'\[?<([0-9A-Fa-f]+)>\]?\s*T[jJ]').allMatches(bruto)) m[1]!,
  ];

  return [
    for (final tabela in tabelas)
      trechos.map((hex) {
        final codigos = <int>[
          for (var i = 0; i + 4 <= hex.length; i += 4)
            tabela[int.parse(hex.substring(i, i + 4), radix: 16)] ?? 0x3F,
        ];
        return String.fromCharCodes(codigos);
      }).join(' '),
  ].join('\n');
}
