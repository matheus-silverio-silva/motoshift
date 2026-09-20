import 'package:flutter/material.dart';

import '../../models/transacao.dart';
import '../../theme/app_theme.dart';

/// Uma linha do extrato.
///
/// O sinal e a cor vêm de [Transacao.credito], que por sua vez lê a coluna
/// `natureza` do backend. Nada aqui decide a direção do dinheiro a partir do
/// tipo: era exatamente assim que uma reserva aparecia como entrada quando o
/// app não conhecia o tipo ainda.
class LancamentoTile extends StatelessWidget {
  const LancamentoTile({
    required this.lancamento,
    this.onTap,
    super.key,
  });

  final Transacao lancamento;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final credito = lancamento.credito;
    final cor = switch (credito) {
      true => AppColors.good,
      false => AppColors.error,
      // Tipo que este app ainda não conhece: valor sem sinal, em tom neutro.
      // Honesto, em vez de rotular como entrada algo que pode ser saída.
      null => AppColors.text,
    };
    final sinal = switch (credito) {
      true => '+',
      false => '−',
      null => '',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            _icone(credito),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lancamento.descricao.isEmpty
                        ? lancamento.tipo.label
                        : lancamento.descricao,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(13, FontWeight.w600, color: AppColors.text),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(lancamento.tipo.label,
                          style: tsJakarta(11, FontWeight.w400,
                              color: AppColors.muted)),
                      if (!lancamento.status.liquidado) ...[
                        const SizedBox(width: 6),
                        _selo(lancamento.status.label),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$sinal${_moeda(lancamento.valor)}',
                  style: tsBricolage(14, FontWeight.w800, color: cor),
                ),
                // O saldo depois do lançamento, quando o backend o gravou.
                // Linhas anteriores à V12 não têm — e a tela omite em vez de
                // mostrar um número reconstruído por aproximação.
                if (lancamento.saldoDisponivelApos != null) ...[
                  const SizedBox(height: 2),
                  Text('saldo ${_moeda(lancamento.saldoDisponivelApos!)}',
                      style: tsJakarta(10, FontWeight.w400,
                          color: AppColors.muted)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _icone(bool? credito) {
    final fundo = switch (credito) {
      true => AppColors.goodSoft,
      false => AppColors.errorContainer,
      null => AppColors.surface3,
    };
    final cor = switch (credito) {
      true => AppColors.good,
      false => AppColors.error,
      null => AppColors.muted,
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(_iconeDoTipo(), size: 18, color: cor),
    );
  }

  IconData _iconeDoTipo() {
    return switch (lancamento.tipo) {
      TipoTransacao.recarga => Icons.add_card_outlined,
      TipoTransacao.saque => Icons.north_east_rounded,
      TipoTransacao.reserva => Icons.lock_outline_rounded,
      TipoTransacao.liberacaoReserva => Icons.lock_open_rounded,
      TipoTransacao.pagamentoEnviado => Icons.arrow_outward_rounded,
      TipoTransacao.pagamentoRecebido ||
      TipoTransacao.turno ||
      TipoTransacao.entrega =>
        Icons.two_wheeler_outlined,
      TipoTransacao.estorno => Icons.undo_rounded,
      TipoTransacao.bonus => Icons.card_giftcard_rounded,
      TipoTransacao.desconhecido => Icons.receipt_long_outlined,
    };
  }

  Widget _selo(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(texto,
          style: tsJakarta(9.5, FontWeight.w700,
              color: AppColors.onTertiaryContainer)),
    );
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}
