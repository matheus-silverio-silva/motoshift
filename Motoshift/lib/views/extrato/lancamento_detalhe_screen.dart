import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/transacao.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/documento/botao_documento.dart';

/// Detalhe de um lançamento.
///
/// Mostra o que o extrato resume: tipo, valor, data, status, contraparte,
/// turno (com link), o identificador da operação e os saldos antes e depois.
///
/// O "antes" não é um campo do backend — é o "depois" menos o efeito deste
/// lançamento, calculado aqui. Guardar os dois seria guardar a mesma
/// informação duas vezes e criar a chance de elas discordarem.
class LancamentoDetalheScreen extends StatelessWidget {
  const LancamentoDetalheScreen({required this.lancamento, super.key});

  final Transacao lancamento;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Lançamento'),
      desktopTitle: 'Lançamento',
      desktopSubtitle: lancamento.tipo.label,
      desktopBody: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _conteudo(context),
        ),
      ),
      body: _conteudo(context),
    );
  }

  Widget _conteudo(BuildContext context) {
    final credito = lancamento.credito;
    final cor = switch (credito) {
      true => AppColors.good,
      false => AppColors.error,
      null => AppColors.text,
    };
    final sinal = switch (credito) {
      true => '+',
      false => '−',
      null => '',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: Column(
            children: [
              Text(lancamento.tipo.label,
                  style: tsJakarta(12.5, FontWeight.w600,
                      color: AppColors.muted)),
              const SizedBox(height: 6),
              Text('$sinal${_moeda(lancamento.valor)}',
                  key: const Key('detalhe-valor'),
                  style: tsBricolage(30, FontWeight.w800, color: cor)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // O documento deste lançamento: NFS-e para pagamento de turno, recibo
        // ou comprovante para o resto. O botão some quando não há documento
        // (lançamento não concluído, Pix ainda pendente).
        if (lancamento.documentoDisponivel) ...[
          if (lancamento.documentoEmitido) ...[
            const Align(alignment: Alignment.center, child: SeloNotaEmitida()),
            const SizedBox(height: 8),
          ],
          BotaoDocumento(lancamento: lancamento),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 8),
        _bloco([
          _linha('Descrição', lancamento.descricao),
          _linha('Data', _dataHora(lancamento.criadoEm)),
          _linha('Status', lancamento.status.label),
          _linha('Direção', switch (credito) {
            true => 'Entrada',
            false => 'Saída',
            null => 'Não informada',
          }),
        ]),
        if (lancamento.contraparteId != null || lancamento.temTurno) ...[
          const SizedBox(height: 14),
          _bloco([
            if (lancamento.contraparteId != null)
              _linha('Contraparte', 'Conta #${lancamento.contraparteId}'),
            if (lancamento.temTurno)
              _linhaComAcao(
                'Turno',
                '#${lancamento.turnoId}',
                'Abrir',
                () => Navigator.of(context).pushNamed(
                  AppRoutes.detalheTurno,
                  arguments: {'turnoId': lancamento.turnoId},
                ),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        _bloco([
          _linha('Saldo antes', _saldoAntes()),
          _linha('Saldo depois', _valorOuTraco(lancamento.saldoDisponivelApos)),
          if (lancamento.saldoBloqueadoApos != null)
            _linha('Bloqueado depois', _moeda(lancamento.saldoBloqueadoApos!)),
        ]),
        if (lancamento.operacaoId != null) ...[
          const SizedBox(height: 14),
          _blocoDaOperacao(context, lancamento.operacaoId!),
        ],
      ],
    );
  }

  /// O saldo imediatamente antes deste lançamento.
  ///
  /// Só existe quando o backend gravou o "depois" — lançamentos anteriores à
  /// V12 não têm snapshot, e a tela mostra um traço em vez de um número
  /// reconstruído por aproximação.
  String _saldoAntes() {
    final depois = lancamento.saldoDisponivelApos;
    if (depois == null) return '—';
    final efeito = switch (lancamento.tipo) {
      TipoTransacao.recarga ||
      TipoTransacao.pagamentoRecebido ||
      TipoTransacao.estorno ||
      TipoTransacao.bonus ||
      TipoTransacao.liberacaoReserva ||
      TipoTransacao.turno ||
      TipoTransacao.entrega =>
        lancamento.valor,
      TipoTransacao.saque ||
      TipoTransacao.reserva ||
      TipoTransacao.retencaoIss ||
      TipoTransacao.retencaoIrrf =>
        -lancamento.valor,
      // Pagamento enviado sai do bloqueado: o disponível não muda.
      TipoTransacao.pagamentoEnviado || TipoTransacao.desconhecido => 0.0,
    };
    return _moeda(depois - efeito);
  }

  Widget _blocoDaOperacao(BuildContext context, String operacaoId) {
    return _bloco([
      _linhaComAcao(
        'Operação',
        operacaoId,
        'Copiar',
        () {
          Clipboard.setData(ClipboardData(text: operacaoId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Identificador copiado.')),
          );
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Este identificador liga os dois lados da transferência: o pagamento '
          'enviado pelo lojista e o recebido pelo entregador são o mesmo evento.',
          style: tsJakarta(11, FontWeight.w400,
              color: AppColors.muted, height: 1.45),
        ),
      ),
    ]);
  }

  Widget _bloco(List<Widget> filhos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: filhos,
      ),
    );
  }

  Widget _linha(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(rotulo,
                style:
                    tsJakarta(12, FontWeight.w500, color: AppColors.muted)),
          ),
          Expanded(
            child: Text(valor.isEmpty ? '—' : valor,
                style: tsJakarta(12.5, FontWeight.w600, color: AppColors.text)),
          ),
        ],
      ),
    );
  }

  Widget _linhaComAcao(
      String rotulo, String valor, String acao, VoidCallback aoTocar) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(rotulo,
                style:
                    tsJakarta(12, FontWeight.w500, color: AppColors.muted)),
          ),
          Expanded(
            child: Text(valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tsJakarta(12.5, FontWeight.w600, color: AppColors.text)),
          ),
          TextButton(onPressed: aoTocar, child: Text(acao)),
        ],
      ),
    );
  }

  static String _valorOuTraco(double? v) => v == null ? '—' : _moeda(v);

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  static String _dataHora(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/'
      '${d.year} às ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
