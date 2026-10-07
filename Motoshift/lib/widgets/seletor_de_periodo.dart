import 'package:flutter/material.dart';

import '../models/extrato_filtro.dart';

/// Os atalhos de período — 7 dias, 30 dias, mês atual, mês anterior — em
/// fichas de escolha.
///
/// Nasceu dentro da tela de relatórios; saiu de lá quando a tela de resultado
/// passou a precisar do mesmo recorte. As duas mostram números do mesmo
/// período lado a lado na cabeça de quem usa, e dois seletores escritos à mão
/// acabariam com rótulos ou datas diferentes.
///
/// [prefixoDaChave] mantém as chaves de cada tela: a de relatórios continua
/// `relatorio-periodo-<atalho>`, que é o que os testes dela procuram.
///
/// As fichas ficam numa linha só, que rola de lado quando não cabe (SCRUM-49).
/// Com quebra de linha, no celular "Mês anterior" caía sozinho na linha de
/// baixo — uma ficha órfã que parecia outro controle.
class SeletorDePeriodo extends StatelessWidget {
  const SeletorDePeriodo({
    required this.selecionado,
    required this.onSelecionar,
    this.prefixoDaChave = 'periodo',
    this.antes = const [],
    this.depois = const [],
    super.key,
  });

  /// O atalho marcado; nulo quando o período da tela não é um atalho (um mês
  /// escolhido no gráfico, por exemplo) — nenhuma ficha fica marcada.
  final AtalhoDePeriodo? selecionado;
  final ValueChanged<AtalhoDePeriodo> onSelecionar;
  final String prefixoDaChave;

  /// Fichas da própria tela, antes dos atalhos. É o lugar do período que não
  /// é atalho (o mês escolhido no gráfico): na frente, ele fica à vista sem
  /// rolar a linha.
  final List<Widget> antes;

  /// Fichas da própria tela, depois dos atalhos.
  final List<Widget> depois;

  @override
  Widget build(BuildContext context) {
    final fichas = <Widget>[
      ...antes,
      for (final a in AtalhoDePeriodo.values)
        ChoiceChip(
          key: Key('$prefixoDaChave-${a.name}'),
          label: Text(a.label),
          selected: selecionado == a,
          onSelected: (_) => onSelecionar(a),
        ),
      ...depois,
    ];
    return SingleChildScrollView(
      key: Key('$prefixoDaChave-linha'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < fichas.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            fichas[i],
          ],
        ],
      ),
    );
  }
}
