/// O que o leitor de tela diz no lugar de um desenho (SCRUM-40).
///
/// Gráfico e mapa são pintados num canvas: para o TalkBack e o VoiceOver não
/// há nada ali, ou há sete rótulos soltos — "Seg", "Ter", "Qua" — sem o valor
/// que cada barra representa. Estas funções montam a frase que substitui o
/// desenho. Ficam fora dos widgets porque são texto puro, e texto puro se
/// testa sem montar tela.
library;

/// "R$ 120" quando o valor é redondo, "R$ 120,50" quando não é.
///
/// Sem os centavos zerados: "cento e vinte reais vírgula zero zero", sete
/// vezes seguidas, é ruído para quem está ouvindo.
String reaisFalados(double valor) {
  final redondo = valor == valor.roundToDouble();
  final texto =
      redondo ? valor.toStringAsFixed(0) : valor.toStringAsFixed(2);
  return 'R\$ ${texto.replaceAll('.', ',')}';
}

/// "5 km" ou "2,5 km".
String kmFalados(double km) {
  final redondo = km == km.roundToDouble();
  final texto = redondo ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
  return '${texto.replaceAll('.', ',')} km';
}

/// "Ganhos dos últimos 7 dias: seg R$ 120, ter R$ 0, ..." — uma barra por
/// trecho, na ordem em que aparecem.
///
/// Com tudo zerado a frase diz isso de uma vez, em vez de recitar sete zeros.
String resumoDeBarras({
  required String titulo,
  required List<String> rotulos,
  required List<double> valores,
}) {
  if (valores.isEmpty || valores.every((v) => v <= 0)) {
    return '$titulo: sem valores no período.';
  }
  final partes = <String>[
    for (var i = 0; i < valores.length; i++)
      '${i < rotulos.length ? rotulos[i].toLowerCase() : 'dia ${i + 1}'} '
          '${reaisFalados(valores[i])}',
  ];
  return '$titulo: ${partes.join(', ')}.';
}

/// "Mapa: Rua das Flores, 100. Raio de 5 km. 3 pontos marcados."
///
/// Só entra o que o mapa de fato desenha: sem raio não se fala em raio, sem
/// pino não se fala em ponto.
String resumoDoMapa({String? local, double? raioKm, int pontos = 0}) {
  final partes = <String>[
    if (local != null && local.trim().isNotEmpty) local.trim(),
    if (raioKm != null && raioKm > 0) 'Raio de ${kmFalados(raioKm)}',
    if (pontos == 1) '1 ponto marcado',
    if (pontos > 1) '$pontos pontos marcados',
  ];
  if (partes.isEmpty) return 'Mapa.';
  return 'Mapa: ${partes.join('. ')}.';
}

/// "Nota 4 de 5", ou "Sem nota" enquanto nenhuma estrela foi marcada.
String resumoDaNota(int nota, {int maximo = 5}) =>
    nota <= 0 ? 'Sem nota' : 'Nota $nota de $maximo';
