import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/serie_diaria.dart';
import 'panel_card.dart';

/// Card do gráfico semanal do dashboard desktop — barras dos últimos 7 dias,
/// valor acima e dia abaixo, com o melhor dia em gradiente (artboards 3 e 4).
class WeeklyBarChartCard extends StatelessWidget {
  const WeeklyBarChartCard({
    required this.title,
    required this.pontos,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.carregando = false,
    this.mensagemVazio = 'Sem movimento nos últimos 7 dias.',
    this.height = 172,
    super.key,
  });

  final String title;
  final List<PontoDiario> pontos;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool carregando;

  /// Texto exibido quando todos os dias da janela estão zerados.
  final String mensagemVazio;
  final double height;

  static const double _gap = 14;
  static const Color _destaqueFg = AppColors.tealDeep;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      gap: 16,
      child: SizedBox(height: height, child: _buildConteudo()),
    );
  }

  Widget _buildConteudo() {
    if (carregando) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.teal),
        ),
      );
    }

    final maxValor = pontos.fold(0.0, (a, p) => p.valor > a ? p.valor : a);
    if (pontos.isEmpty || maxValor <= 0) return _buildVazio();

    final destaque = pontos.indexWhere((p) => p.valor == maxValor);

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraBarra =
            ((constraints.maxWidth - _gap * (pontos.length - 1)) /
                    pontos.length)
                .clamp(4.0, 64.0);

        return BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceBetween,
            // Folga no topo para o rótulo de valor caber acima da barra mais
            // alta, como no protótipo (lá o rótulo é um item do flex acima da
            // barra, então a barra de 100% já nasce descontando esse espaço).
            maxY: maxValor * 1.2,
            minY: 0,
            barTouchData: BarTouchData(
              enabled: false,
              touchTooltipData: BarTouchTooltipData(
                // O "tooltip" aqui é só o rótulo de valor acima da barra:
                // sem fundo, sem borda, sem respiro.
                getTooltipColor: (_) => Colors.transparent,
                tooltipPadding: EdgeInsets.zero,
                tooltipMargin: 6,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final destacado = group.x == destaque;
                  return BarTooltipItem(
                    'R\$ ${rod.toY.toStringAsFixed(0)}',
                    tsJakarta(
                      11,
                      destacado ? FontWeight.w800 : FontWeight.w700,
                      color: destacado ? _destaqueFg : AppColors.muted,
                    ),
                  );
                },
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (valor, meta) => _rotuloDia(valor, destaque),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < pontos.length; i++)
                BarChartGroupData(
                  x: i,
                  showingTooltipIndicators: const [0],
                  barRods: [
                    BarChartRodData(
                      toY: pontos[i].valor,
                      width: larguraBarra,
                      color: i == destaque ? null : AppColors.tealSoft,
                      gradient: i == destaque
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AppColors.tealBright, AppColors.teal],
                            )
                          : null,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _rotuloDia(double valor, int destaque) {
    final i = valor.toInt();
    if (i < 0 || i >= pontos.length) return const SizedBox.shrink();
    final destacado = i == destaque;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        pontos[i].label,
        style: tsJakarta(
          11,
          destacado ? FontWeight.w800 : FontWeight.w700,
          color: destacado ? _destaqueFg : AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bar_chart_outlined,
                size: 22, color: AppColors.tealDeep),
          ),
          const SizedBox(height: 12),
          Text(
            mensagemVazio,
            textAlign: TextAlign.center,
            style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
