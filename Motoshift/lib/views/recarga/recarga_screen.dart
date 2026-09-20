import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/cobranca.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';

/// Adicionar saldo: gera uma cobrança Pix simulada e a confirma.
///
/// São dois passos porque o fluxo real também é: criar a cobrança não credita
/// nada, e o dinheiro só entra quando o provedor avisa que foi pago. O botão
/// "Simular pagamento" ocupa o lugar desse aviso — ele chama o endpoint que
/// imita o webhook, e é a única parte fingida da tela.
class RecargaScreen extends StatefulWidget {
  const RecargaScreen({super.key, this.valorSugerido});

  /// Quanto falta para publicar um turno, quando a tela é aberta a partir de
  /// uma publicação recusada por saldo.
  final double? valorSugerido;

  @override
  State<RecargaScreen> createState() => _RecargaScreenState();
}

class _RecargaScreenState extends State<RecargaScreen> {
  static const List<double> _atalhos = [50, 100, 200, 500];

  final TextEditingController _valor = TextEditingController();

  Cobranca? _cobranca;
  bool _ocupado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.valorSugerido != null) {
      // Arredonda para cima, em dezenas: ninguém recarrega R$ 163,47.
      final sugerido = (widget.valorSugerido! / 10).ceil() * 10;
      _valor.text = sugerido.toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  double? get _valorDigitado {
    final texto = _valor.text.replaceAll('.', '').replaceAll(',', '.');
    final v = double.tryParse(texto);
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _gerarCobranca() async {
    final valor = _valorDigitado;
    if (valor == null) {
      setState(() => _erro = 'Informe um valor maior que zero.');
      return;
    }
    await _executar(() async {
      final c = await context.read<ApiService>().carteira.criarRecarga(valor);
      if (mounted) setState(() => _cobranca = c);
    });
  }

  Future<void> _simularPagamento() async {
    final cobranca = _cobranca;
    if (cobranca == null) return;
    await _executar(() async {
      final c = await context
          .read<ApiService>()
          .carteira
          .confirmarRecarga(cobranca.id);
      if (!mounted) return;
      setState(() => _cobranca = c);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Recarga de ${_moeda(c.valor)} confirmada!'),
        backgroundColor: AppColors.good,
      ));
      // `true` avisa a tela anterior de que o saldo mudou.
      Navigator.of(context).pop(true);
    });
  }

  Future<void> _executar(Future<void> Function() acao) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await acao();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível concluir a recarga.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Adicionar saldo'),
      desktopTitle: 'Adicionar saldo',
      desktopSubtitle: 'Recarregue a carteira via Pix',
      desktopBody: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _conteudo(),
        ),
      ),
      body: _conteudo(),
    );
  }

  Widget _conteudo() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (widget.valorSugerido != null) _avisoDeSaldoFaltante(),
        if (_cobranca == null) ..._passoDoValor() else ..._passoDoPagamento(),
        if (_erro != null) ...[
          const SizedBox(height: 14),
          _caixaDeErro(_erro!),
        ],
      ],
    );
  }

  Widget _avisoDeSaldoFaltante() {
    return Container(
      key: const Key('recarga-aviso-saldo'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: AppColors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Faltam ${_moeda(widget.valorSugerido!)} para publicar o turno. '
              'O valor abaixo já vem preenchido.',
              style: tsJakarta(12, FontWeight.w500,
                  color: AppColors.onTertiaryContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Passo 1: quanto ──────────────────────────────────────────────────────

  List<Widget> _passoDoValor() {
    return [
      Text('Quanto você quer adicionar?',
          style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 14),
      TextField(
        key: const Key('recarga-valor'),
        controller: _valor,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Valor (R\$)',
          prefixText: 'R\$ ',
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in _atalhos)
            ActionChip(
              key: Key('recarga-atalho-${v.toInt()}'),
              label: Text('R\$ ${v.toInt()}'),
              onPressed: () => setState(
                  () => _valor.text = v.toStringAsFixed(2).replaceAll('.', ',')),
            ),
        ],
      ),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('recarga-gerar'),
        onPressed: _ocupado || _valorDigitado == null ? null : _gerarCobranca,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: AppColors.teal,
        ),
        child: _ocupado
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Text('Gerar código Pix'),
      ),
    ];
  }

  // ── Passo 2: pagar ───────────────────────────────────────────────────────

  List<Widget> _passoDoPagamento() {
    final c = _cobranca!;
    return [
      Text('Pague ${_moeda(c.valor)}',
          style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 4),
      Text('Copie o código abaixo no app do seu banco.',
          style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted)),
      const SizedBox(height: 16),
      _quadroDoQr(c),
      const SizedBox(height: 14),
      _codigoCopiaECola(c),
      const SizedBox(height: 18),
      _avisoDeSimulacao(),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const Key('recarga-simular'),
        onPressed: _ocupado ? null : _simularPagamento,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Simular pagamento'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: AppColors.good,
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _ocupado ? null : () => setState(() => _cobranca = null),
        child: const Text('Alterar valor'),
      ),
    ];
  }

  /// O "QR" é um bloco decorativo com o ícone: desenhar um QR de verdade a
  /// partir de um código inválido daria a impressão de que ele poderia ser
  /// escaneado, e ele não pode.
  Widget _quadroDoQr(Cobranca c) {
    return Center(
      child: Container(
        key: const Key('recarga-qr'),
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_2, size: 84, color: AppColors.ink),
            const SizedBox(height: 6),
            Text('Pix simulado',
                style: tsJakarta(11, FontWeight.w600, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _codigoCopiaECola(Cobranca c) {
    final codigo = c.codigoPix ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              codigo,
              key: const Key('recarga-codigo'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tsJakarta(11, FontWeight.w400, color: AppColors.text),
            ),
          ),
          IconButton(
            tooltip: 'Copiar código',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: codigo));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Código copiado.'),
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _avisoDeSimulacao() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined, size: 17, color: AppColors.muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Este é um gateway simulado: o código Pix não é válido em banco '
              'nenhum. O botão abaixo faz o papel do aviso de pagamento que o '
              'provedor real enviaria.',
              style: tsJakarta(11.5, FontWeight.w400,
                  color: AppColors.muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _caixaDeErro(String mensagem) {
    return Container(
      key: const Key('recarga-erro'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 17, color: AppColors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(mensagem,
                style: tsJakarta(12, FontWeight.w500, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}
