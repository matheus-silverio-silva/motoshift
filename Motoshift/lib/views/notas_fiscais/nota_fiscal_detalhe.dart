import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/nota_fiscal.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

/// O documento aberto: partes, serviço, tributos e valor líquido.
///
/// A ordem segue a de uma NFS-e — quem presta, quem toma, o que foi feito,
/// quanto custou, o que foi retido e o que sobra. O cancelamento fica no fim e
/// só aparece para o prestador, que é de quem é o documento.
class NotaFiscalDetalhe extends StatefulWidget {
  const NotaFiscalDetalhe({
    required this.nota,
    this.onCancelada,
    super.key,
  });

  final NotaFiscal nota;

  /// Avisa a lista para trocar a nota pela versão cancelada, sem recarregar
  /// tudo do servidor.
  final ValueChanged<NotaFiscal>? onCancelada;

  @override
  State<NotaFiscalDetalhe> createState() => _NotaFiscalDetalheState();
}

class _NotaFiscalDetalheState extends State<NotaFiscalDetalhe> {
  late NotaFiscal _nota = widget.nota;
  bool _cancelando = false;

  Future<void> _cancelar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar nota fiscal',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          'A NFS-e ${_nota.numeroFormatado} passa a constar como cancelada '
          'para as duas partes. A numeração não é reaproveitada.',
          style: tsJakarta(13, FontWeight.w400,
              color: AppColors.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar',
                style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar nota',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _cancelando = true);
    try {
      final atualizada =
          await context.read<ApiService>().notasFiscais.cancelar(_nota.id);
      if (!mounted) return;
      setState(() {
        _nota = atualizada;
        _cancelando = false;
      });
      widget.onCancelada?.call(atualizada);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final alturaMaxima = MediaQuery.of(context).size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: alturaMaxima),
      decoration: const BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPuxador(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: [
                _buildCabecalho(),
                const SizedBox(height: 14),
                _buildPartes(),
                const SizedBox(height: 12),
                _buildServico(),
                const SizedBox(height: 12),
                _buildTributos(),
                if (_nota.cancelada) ...[
                  const SizedBox(height: 12),
                  _buildAvisoCancelada(),
                ] else if (_nota.souPrestador) ...[
                  const SizedBox(height: 16),
                  _buildBotaoCancelar(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPuxador() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildCabecalho() {
    final emitida =
        DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(_nota.emitidaEm);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOTA FISCAL DE SERVIÇO ELETRÔNICA',
              style: tsJakarta(9, FontWeight.w700, color: Colors.white70)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 6),
          Text('Nº ${_nota.numeroFormatado}',
              style: tsBricolage(24, FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Emitida em $emitida',
              style: tsJakarta(11, FontWeight.w400, color: Colors.white70)),
          const SizedBox(height: 2),
          Text('Código de verificação: ${_nota.codigoVerificacao}',
              style: tsJakarta(11, FontWeight.w600, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildPartes() {
    return _Cartao(
      titulo: 'Partes',
      child: Column(
        children: [
          _Parte(
            rotulo: 'Prestador do serviço',
            nome: _nota.prestadorNome,
            documento: _nota.prestadorDocumento,
            destaque: _nota.souPrestador,
            icone: Icons.two_wheeler_outlined,
          ),
          const SizedBox(height: 10),
          _Parte(
            rotulo: 'Tomador do serviço',
            nome: _nota.tomadorNome,
            documento: _nota.tomadorDocumento,
            destaque: !_nota.souPrestador,
            icone: Icons.storefront_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildServico() {
    final competencia = _nota.competencia;
    return _Cartao(
      titulo: 'Serviço',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_nota.descricaoServico,
              style: tsJakarta(12, FontWeight.w400,
                  color: AppColors.text, height: 1.5)),
          if (competencia != null) ...[
            const SizedBox(height: 8),
            _Linha(
              rotulo: 'Competência',
              valor: DateFormat('dd/MM/yyyy', 'pt_BR').format(competencia),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTributos() {
    return _Cartao(
      titulo: 'Valores e tributos',
      child: Column(
        children: [
          _Linha(
            rotulo: 'Valor do serviço (base de cálculo)',
            valor: _moeda(_nota.valorServico),
            forte: true,
          ),
          const SizedBox(height: 8),
          _Linha(
            rotulo: 'ISS (${_percentual(_nota.issAliquota)})',
            valor: '− ${_moeda(_nota.issValor)}',
          ),
          const SizedBox(height: 6),
          _Linha(
            rotulo: 'IRRF (${_percentual(_nota.irrfAliquota)})',
            valor: '− ${_moeda(_nota.irrfValor)}',
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
          _Linha(
            rotulo: 'Total de tributos retidos',
            valor: _moeda(_nota.totalTributos),
          ),
          const SizedBox(height: 8),
          _Linha(
            rotulo: 'Valor líquido',
            valor: _moeda(_nota.valorLiquido),
            forte: true,
            destaque: true,
          ),
          const SizedBox(height: 10),
          Text(
            'Alíquotas de exemplo, para demonstrar a composição do documento. '
            'Uma emissão real usa a tabela do município do prestador.',
            style: tsJakarta(10, FontWeight.w400, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoCancelada() {
    final quando = _nota.canceladaEm;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Nota cancelada',
                    style: tsJakarta(12.5, FontWeight.w800,
                        color: AppColors.error)),
                if (quando != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(quando),
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted),
                  ),
                ],
                if (_nota.motivoCancelamento != null) ...[
                  const SizedBox(height: 4),
                  Text(_nota.motivoCancelamento!,
                      style: tsJakarta(11, FontWeight.w400,
                          color: AppColors.text)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoCancelar() {
    return TextButton.icon(
      onPressed: _cancelando ? null : _cancelar,
      icon: _cancelando
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.error),
            )
          : const Icon(Icons.block_rounded, size: 17),
      label: Text('Cancelar nota fiscal',
          style: tsJakarta(12.5, FontWeight.w700, color: AppColors.error)),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.error,
        minimumSize: const Size(0, 48),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _moeda(double valor) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);

  /// 0.05 → "5%"; 0.015 → "1,5%".
  String _percentual(double aliquota) {
    final pct = aliquota * 100;
    final texto = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    return '${texto.replaceAll('.', ',')}%';
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Parte extends StatelessWidget {
  const _Parte({
    required this.rotulo,
    required this.nome,
    required this.destaque,
    required this.icone,
    this.documento,
  });

  final String rotulo;
  final String nome;
  final String? documento;

  /// Marca qual dos dois lados é o usuário que está olhando.
  final bool destaque;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: destaque ? AppColors.tealSoft : AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone,
              size: 17,
              color: destaque ? AppColors.tealDeep : AppColors.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(rotulo,
                      style: tsJakarta(10, FontWeight.w600,
                          color: AppColors.muted)),
                  if (destaque) ...[
                    const SizedBox(width: 5),
                    Text('· você',
                        style: tsJakarta(10, FontWeight.w700,
                            color: AppColors.teal)),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tsJakarta(12.5, FontWeight.w700, color: AppColors.ink)),
              if (documento != null && documento!.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(documento!,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.rotulo,
    required this.valor,
    this.forte = false,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final bool forte;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final cor = destaque ? AppColors.tealDeep : AppColors.ink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(rotulo,
              style: tsJakarta(11.5, forte ? FontWeight.w700 : FontWeight.w400,
                  color: forte ? AppColors.text : AppColors.muted)),
        ),
        const SizedBox(width: 10),
        Text(valor,
            style: tsJakarta(
                destaque ? 14 : 12, forte ? FontWeight.w800 : FontWeight.w600,
                color: forte ? cor : AppColors.text)),
      ],
    );
  }
}
