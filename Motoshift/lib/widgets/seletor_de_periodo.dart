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
class SeletorDePeriodo extends StatelessWidget {
  const SeletorDePeriodo({
    required this.selecionado,
    required this.onSelecionar,
    this.prefixoDaChave = 'periodo',
    this.depois = const [],
    super.key,
  });

  /// O atalho marcado; nulo quando o período da tela não é um atalho (um mês
  /// escolhido no gráfico, por exemplo) — nenhuma ficha fica marcada.
  final AtalhoDePeriodo? selecionado;
  final ValueChanged<AtalhoDePeriodo> onSelecionar;
  final String prefixoDaChave;

  /// Fichas da própria tela, depois dos atalhos.
  final List<Widget> depois;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in AtalhoDePeriodo.values)
          ChoiceChip(
            key: Key('$prefixoDaChave-${a.name}'),
            label: Text(a.label),
            selected: selecionado == a,
            onSelected: (_) => onSelecionar(a),
          ),
        ...depois,
      ],
    );
  }
}
