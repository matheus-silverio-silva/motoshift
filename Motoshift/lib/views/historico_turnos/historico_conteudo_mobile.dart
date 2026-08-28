import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/turno.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';
import 'historico_filtros.dart';
import 'historico_resumo.dart';

/// Histórico no celular: três células de resumo, pílulas de filtro roláveis e
/// um card por turno, com as ações embaixo de quem precisa delas.
///
/// Separado do desktop porque os dois moravam no mesmo `State` de 1.100
/// linhas: qualquer mexida num layout passava perto do outro sem necessidade.
class HistoricoConteudoMobile extends StatelessWidget {
  const HistoricoConteudoMobile({
    required this.resumo,
    required this.filtro,
    required this.isLojista,
    required this.onFiltro,
    required this.onRecarregar,
    required this.onAbrirTurno,
    required this.onAvaliar,
    required this.onPagar,
    super.key,
  });

  final HistoricoResumo resumo;
  final String filtro;
  final bool isLojista;
  final ValueChanged<String> onFiltro;
  final Future<void> Function() onRecarregar;
  final ValueChanged<Turno> onAbrirTurno;
  final ValueChanged<Turno> onAvaliar;

  /// Confirmar pagamento (lojista) ou recebimento (motoboy). Para turno
  /// multi-vaga do lojista, quem hospeda abre o painel por entregador.
  final ValueChanged<Turno> onPagar;

  @override
  Widget build(BuildContext context) {
    final filtrados = resumo.filtrar(filtro);

    return RefreshIndicator(
      onRefresh: onRecarregar,
      color: AppColors.teal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
        children: [
          _buildResumo(),
          const SizedBox(height: 16),
          _buildFiltros(),
          const SizedBox(height: 14),
          if (filtrados.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Center(
                child: Text(
                  'Nenhum turno nesse filtro.',
                  style: tsJakarta(12, FontWeight.w400,
                      color: AppColors.muted),
                ),
              ),
            )
          else
            ...filtrados.map(_buildTurnoCard),
        ],
      ),
    );
  }


  Widget _buildResumo() {
    final labelPendente =
        isLojista ? 'A PAGAR' : 'A RECEBER';

    return Row(
      children: [
        Expanded(
          child: _statCell(
            label: 'A AVALIAR',
            value: '${resumo.qtdAvaliar}',
            iconData: Icons.star_outline_rounded,
            highlight: resumo.qtdAvaliar > 0,
            color: resumo.qtdAvaliar > 0 ? AppColors.amber : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCell(
            label: labelPendente,
            value: 'R\$ ${resumo.valorPendente.toStringAsFixed(0)}',
            iconData: Icons.schedule_rounded,
            highlight: resumo.qtdPagamento > 0,
            color: resumo.qtdPagamento > 0 ? AppColors.amber : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCell(
            label: isLojista ? 'GASTO PAGO' : 'RECEBIDO',
            value: 'R\$ ${resumo.totalGanho.toStringAsFixed(0)}',
            iconData: Icons.check_circle_outline_rounded,
            highlight: true,
          ),
        ),
      ],
    );
  }
  Widget _statCell({
    required String label,
    required String value,
    required IconData iconData,
    bool highlight = false,
    Color? color,
  }) {
    final accent = color ?? AppColors.tealDeep;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 11),
      decoration: BoxDecoration(
        color: highlight
            ? (color == AppColors.amber
                ? AppColors.amberSoft
                : AppColors.tealSoft)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight ? accent.withOpacity(0.4) : AppColors.line,
            width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(iconData,
                  size: 13,
                  color: highlight ? accent : AppColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(8.5, FontWeight.w700,
                        color:
                            highlight ? accent : AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: tsBricolage(16, FontWeight.w800,
                    color: highlight ? accent : AppColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opcoesFiltroHistorico(resumo, isLojista).map((op) {
          final sel = filtro == op.chave;
          final count = op.contagem;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => onFiltro(op.chave),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? AppColors.teal : AppColors.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: sel ? AppColors.teal : AppColors.line,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      op.rotulo,
                      style: tsJakarta(12, FontWeight.w700,
                          color: sel ? Colors.white : AppColors.muted),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: sel
                              ? Colors.white24
                              : AppColors.surface3,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$count',
                          style: tsJakarta(9.5, FontWeight.w800,
                              color: sel
                                  ? Colors.white
                                  : AppColors.muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTurnoCard(Turno t) {
    final dataFmt =
        DateFormat('dd/MM/yyyy', 'pt_BR').format(t.dataInicio);
    final precisaAvaliar = resumo.precisaAvaliar(t);
    final aguardaPagto = resumo.aguardandoPagamento(t);

    // Determina label/cor da pill conforme estado de confirmação
    PillVariant pill;
    String pillLabel;
    if (t.status == StatusTurno.cancelado ||
        t.status == StatusTurno.expirado) {
      pill = PillVariant.ghost;
      pillLabel = t.status.label;
    } else if (aguardaPagto) {
      pill = PillVariant.amber;
      if (isLojista) {
        pillLabel = t.lojistaJaConfirmou
            ? 'Aguardando motoboy'
            : 'A confirmar';
      } else {
        pillLabel = t.motoboyJaConfirmou
            ? 'Aguardando lojista'
            : (t.lojistaJaConfirmou
                ? 'Confirme recebimento'
                : 'A receber');
      }
    } else if (t.pagamentoStatus == PagamentoStatus.pago) {
      pill = PillVariant.good;
      pillLabel = 'Pago';
    } else {
      pill = PillVariant.ghost;
      pillLabel = 'Finalizado';
    }

    final podeConfirmarPgto = aguardaPagto &&
        (isLojista
            ? resumo.lojistaPrecisaConfirmar(t)
            : resumo.motoboyPrecisaConfirmar(t));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ShiftCard(
            horario: dataFmt,
            name: t.titulo,
            meta: [t.regiao],
            value: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
            iconData: isLojista
                ? Icons.store_outlined
                : Icons.two_wheeler_outlined,
            pillLabel: pillLabel,
            pillVariant: pill,
            onTap: () => onAbrirTurno(t),
          ),
          if (aguardaPagto && !podeConfirmarPgto)
            _buildEsperandoOutraParte(t),
          if (precisaAvaliar || podeConfirmarPgto)
            _buildAcoes(t, precisaAvaliar, podeConfirmarPgto),
        ],
      ),
    );
  }

  Widget _buildEsperandoOutraParte(Turno t) {
    final texto = isLojista
        ? 'Você confirmou. Aguardando o motoboy confirmar o recebimento.'
        : 'Você confirmou. Aguardando o lojista confirmar o pagamento.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.teal.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top_rounded,
                size: 14, color: AppColors.tealDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texto,
                  style: tsJakarta(11.5, FontWeight.w600,
                      color: AppColors.tealDeep, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcoes(
      Turno t, bool podeAvaliar, bool podePagar) {
    final labelPgto = isLojista
        ? 'Confirmar pagamento'
        : 'Confirmar recebimento';
    final iconPgto = isLojista
        ? Icons.payments_rounded
        : Icons.check_circle_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          if (podeAvaliar) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onAvaliar(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.amberSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.amber.withOpacity(0.4),
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_outline_rounded,
                          size: 14, color: AppColors.onTertiaryContainer),
                      const SizedBox(width: 6),
                      Text('Avaliar',
                          style: tsJakarta(12, FontWeight.w700,
                              color: AppColors.onTertiaryContainer)),
                    ],
                  ),
                ),
              ),
            ),
            if (podePagar) const SizedBox(width: 8),
          ],
          if (podePagar)
            Expanded(
              child: GestureDetector(
                onTap: () => onPagar(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconPgto,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(labelPgto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tsJakarta(12, FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
