import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/turno.dart';
import '../../theme/app_theme.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_pill.dart';
import 'historico_filtros.dart';
import 'historico_resumo.dart';

/// Histórico no desktop: linha de KPIs e uma tabela com filtros.
///
/// Vive fora do `State` da tela — o arquivo tinha mobile e desktop no mesmo
/// lugar, e mexer num arriscava o outro. Aqui a única entrada é o [resumo],
/// que é dado, e as saídas são callbacks.
class HistoricoConteudoDesktop extends StatelessWidget {
  const HistoricoConteudoDesktop({
    required this.resumo,
    required this.filtro,
    required this.isLojista,
    required this.onFiltro,
    required this.onAbrirTurno,
    super.key,
  });

  final HistoricoResumo resumo;
  final String filtro;
  final bool isLojista;
  final ValueChanged<String> onFiltro;
  final ValueChanged<Turno> onAbrirTurno;

  @override
  Widget build(BuildContext context) {
    return ContentGrid(
      children: [
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: 'Turnos concluídos',
            value: '${resumo.qtdFinalizados}',
            sub: '${resumo.percentualConclusao}% de conclusão',
          ),
        ),
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: isLojista ? 'Total pago' : 'Total recebido',
            value: 'R\$ ${resumo.totalGanho.toStringAsFixed(0)}',
            sub: 'média R\$ ${resumo.mediaPorTurno.toStringAsFixed(0)}',
            subColor: AppColors.muted,
          ),
        ),
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: 'Cancelados',
            value: '${resumo.qtdCancelados}',
            // Os expirados entram como subtexto: não cabe um quinto card no
            // grid de 12 colunas, mas o estado precisa aparecer em algum lugar
            // desta linha — senão volta a ser invisível.
            sub: resumo.qtdExpirados > 0
                ? '+ ${resumo.qtdExpirados} '
                    '${resumo.qtdExpirados == 1 ? 'expirado' : 'expirados'}'
                : (resumo.qtdCancelados == 0 ? 'nenhum' : 'no período'),
            subColor: resumo.qtdCancelados > 0 || resumo.qtdExpirados > 0
                ? AppColors.amber
                : AppColors.muted,
          ),
        ),
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: 'Horas rodadas',
            value: '${resumo.horasRodadas.toStringAsFixed(0)} h',
            sub: '${resumo.mediaHoras.toStringAsFixed(1).replaceAll('.', ',')} h '
                'por turno',
            subColor: AppColors.muted,
          ),
        ),
        GridCol(
          span: 12,
          child: PanelCard(
            padding: const EdgeInsets.all(22),
            gap: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFiltros(),
                const SizedBox(height: 14),
                _buildTabela(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltros() {
    return Row(
      children: [
        for (final op in opcoesFiltroHistorico(resumo, isLojista)) ...[
          InkWell(
            onTap: () => onFiltro(op.chave),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: filtro == op.chave ? AppColors.teal : AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(
                    op.rotulo,
                    style: tsJakarta(12, FontWeight.w700,
                        color: filtro == op.chave
                            ? Colors.white
                            : AppColors.muted),
                  ),
                  if (op.contagem > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${op.contagem}',
                      style: tsJakarta(11, FontWeight.w800,
                          color: filtro == op.chave
                              ? Colors.white70
                              : AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// Colunas: turno · data · região · status · valor.
  ///
  /// O artboard traz "LOJISTA" na terceira coluna, mas o turno só carrega
  /// `lojistId` — o nome exigiria uma busca por turno. Fica a região, que é
  /// dado que a lista já tem.
  Widget _buildTabela() {
    const flexes = [26, 16, 20, 15, 14];
    final linhas = resumo.filtrar(filtro);

    Widget celula(int i, Widget filho, {bool fim = false}) => Expanded(
          flex: flexes[i],
          child: Align(
            alignment: fim ? Alignment.centerRight : Alignment.centerLeft,
            child: filho,
          ),
        );

    Widget cabecalho(String texto) => Text(
          texto,
          style: tsJakarta(10.5, FontWeight.w700, color: AppColors.muted)
              .copyWith(letterSpacing: 10.5 * .08),
        );

    if (linhas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('Nenhum turno nesse filtro.',
              style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.line, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              celula(0, cabecalho('TURNO')),
              celula(1, cabecalho('DATA')),
              celula(2, cabecalho('REGIÃO')),
              celula(3, cabecalho('STATUS')),
              celula(4, cabecalho('VALOR'), fim: true),
            ],
          ),
        ),
        for (final t in linhas) _buildLinha(t, celula),
      ],
    );
  }

  Widget _buildLinha(
    Turno t,
    Widget Function(int, Widget, {bool fim}) celula,
  ) {
    // Cancelado e expirado terminam sem entrega e sem dinheiro trocando de
    // mão: mesmo tratamento visual (apagado), rótulo próprio de cada um.
    final semEntrega = resumo.semEntrega(t);
    final pago = t.pagamentoStatus == PagamentoStatus.pago;

    final (String rotulo, PillVariant variante) = semEntrega
        ? (t.status.label, PillVariant.ghost)
        : pago
            ? ('Pago', PillVariant.good)
            : resumo.aguardandoPagamento(t)
                ? (isLojista ? 'A pagar' : 'A receber', PillVariant.amber)
                : ('Finalizado', PillVariant.ghost);

    return InkWell(
      onTap: () => onAbrirTurno(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            celula(
              0,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tsJakarta(13, FontWeight.w700,
                          color: semEntrega ? AppColors.muted : AppColors.text)),
                  Text(
                    '${t.horarioFormatado} · '
                    '${t.raioEntregaKm.toStringAsFixed(0)} km',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tsJakarta(11, FontWeight.w400, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            celula(
              1,
              Text(DateFormat('dd/MM/yyyy', 'pt_BR').format(t.dataInicio),
                  style: tsJakarta(12.5, FontWeight.w400,
                      color: AppColors.muted)),
            ),
            celula(
              2,
              Text(t.regiao,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tsJakarta(12.5, FontWeight.w400, color: AppColors.text)),
            ),
            celula(3, StatusPill(label: rotulo, variant: variante)),
            celula(
              4,
              Text(
                'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                style: tsBricolage(15, FontWeight.w800,
                    color: semEntrega ? AppColors.muted : AppColors.ink),
              ),
              fim: true,
            ),
          ],
        ),
      ),
    );
  }
}
