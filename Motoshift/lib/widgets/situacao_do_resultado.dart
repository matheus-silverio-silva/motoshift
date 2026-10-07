import 'package:flutter/material.dart';

import '../models/dre.dart';
import '../theme/app_theme.dart';
import '../utils/formato_fiscal.dart';

/// As cores e o ícone de cada situação da DRE — lucro, prejuízo, equilíbrio.
///
/// Um lugar só: a faixa da tela de resultado, o cartão "Resultado do mês" dos
/// painéis e os indicadores dizem a mesma situação, e têm de dizê-la com a
/// mesma cara. A cor nunca vai sozinha — quem usa isto põe junto o rótulo
/// ("Lucro", "Prejuízo") ou a frase.
class VisualDaSituacao {
  const VisualDaSituacao._(this.fundo, this.borda, this.cor, this.icone);

  final Color fundo;
  final Color borda;

  /// A cor do texto e do ícone: escura o bastante para texto pequeno sobre o
  /// [fundo] e sobre o branco.
  final Color cor;
  final IconData icone;

  static const lucro = VisualDaSituacao._(AppColors.goodSoft, AppColors.good,
      Color(0xFF0B5C43), Icons.trending_up_rounded);
  static const prejuizo = VisualDaSituacao._(AppColors.errorContainer,
      AppColors.error, Color(0xFF8C1212), Icons.trending_down_rounded);
  static const equilibrio = VisualDaSituacao._(AppColors.surface2,
      AppColors.line, AppColors.tealDeep, Icons.drag_handle_rounded);

  static VisualDaSituacao de(SituacaoDre situacao) => switch (situacao) {
        SituacaoDre.lucro => lucro,
        SituacaoDre.prejuizo => prejuizo,
        SituacaoDre.equilibrio => equilibrio,
      };
}

/// O ícone com o rótulo embaixo — "Lucro", "Prejuízo", "Equilíbrio".
class SeloDeSituacao extends StatelessWidget {
  const SeloDeSituacao(this.situacao, {this.chaveDoRotulo, super.key});

  final SituacaoDre situacao;
  final Key? chaveDoRotulo;

  @override
  Widget build(BuildContext context) {
    final visual = VisualDaSituacao.de(situacao);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: visual.borda, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icone, size: 22, color: visual.cor),
          const SizedBox(height: 2),
          Text(situacao.rotulo,
              key: chaveDoRotulo,
              style: tsJakarta(10.5, FontWeight.w800, color: visual.cor)),
        ],
      ),
    );
  }
}

/// O cartão "Resultado do mês" dos dois painéis (SCRUM-49).
///
/// Responde no painel a pergunta que antes pedia abrir o menu: "estou tendo
/// lucro?". Mostra a situação por extenso — "Lucro de R$ 111,95" —, com o
/// selo da tela de resultado, e leva até ela.
///
/// Sem nada informado à mão no mês, o número seria só o que passou pela
/// plataforma: o cartão não o mostra como resposta, e convida a informar os
/// custos — o toque abre o formulário.
///
/// O painel busca a DRE e entrega aqui; se a busca falhou, ele nem monta o
/// cartão.
class CartaoResultadoDoMes extends StatelessWidget {
  const CartaoResultadoDoMes({
    required this.dre,
    required this.aoAbrirResultado,
    required this.aoInformar,
    super.key,
  });

  final Dre dre;
  final VoidCallback aoAbrirResultado;
  final VoidCallback aoInformar;

  /// O convite de quando nada foi informado. O entregador informa custos; o
  /// lojista, antes de tudo, a taxa de entrega que cobrou.
  static String convite({required bool lojista}) => lojista
      ? 'Informe as taxas de entrega para ver o lucro real'
      : 'Informe seus custos para ver o lucro real';

  /// "Lucro de R$ 111,95", "Prejuízo de R$ 308,05" ou "Sem lucro nem prejuízo".
  static String situacaoPorExtenso(Dre dre) => switch (dre.situacao) {
        SituacaoDre.lucro => 'Lucro de ${FormatoFiscal.moeda(dre.resultado.abs())}',
        SituacaoDre.prejuizo =>
          'Prejuízo de ${FormatoFiscal.moeda(dre.resultado.abs())}',
        SituacaoDre.equilibrio => 'Sem lucro nem prejuízo',
      };

  @override
  Widget build(BuildContext context) {
    final semLancamentos = dre.lancamentosManuais == 0;
    final texto =
        semLancamentos ? convite(lojista: dre.souLojista) : situacaoPorExtenso(dre);
    final apoio = semLancamentos
        ? 'Até aqui o resultado só conhece o que passou pela plataforma.'
        : 'Toque para ver a demonstração';
    final visual = VisualDaSituacao.de(dre.situacao);
    final aoTocar = semLancamentos ? aoInformar : aoAbrirResultado;

    return Semantics(
      container: true,
      button: true,
      label: 'Resultado do mês. $texto. '
          '${semLancamentos ? 'Abrir o formulário de lançamento' : 'Abrir o resultado'}',
      onTap: aoTocar,
      excludeSemantics: true,
      child: Material(
        color: semLancamentos ? AppColors.amberSoft : visual.fundo,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('painel-resultado-do-mes'),
          borderRadius: BorderRadius.circular(14),
          onTap: aoTocar,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: semLancamentos ? AppColors.amber : visual.borda,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                if (semLancamentos)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.edit_note_rounded,
                        size: 26, color: AppColors.onTertiaryContainer),
                  )
                else
                  SeloDeSituacao(dre.situacao),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('RESULTADO DO MÊS',
                          style: tsJakarta(9, FontWeight.w700,
                              color: AppColors.mutedTexto)),
                      const SizedBox(height: 2),
                      Text(texto,
                          key: const Key('painel-resultado-texto'),
                          style: tsBricolage(
                              semLancamentos ? 14 : 16, FontWeight.w800,
                              color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(apoio,
                          style: tsJakarta(11, FontWeight.w600,
                              color: AppColors.mutedTexto)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 22, color: AppColors.mutedTexto),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
