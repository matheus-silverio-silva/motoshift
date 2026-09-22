import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/documento_fiscal.dart';
import '../../models/nota_fiscal.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/documento/acoes_documento.dart';
import '../../widgets/documento/nfse_view.dart';

/// O documento aberto: partes, serviço, tributos e valor líquido.
///
/// O layout saiu daqui para [NfseView] quando o extrato passou a abrir notas
/// também — eram duas telas desenhando a mesma nota, e só uma delas ganhava
/// cada correção. Aqui ficou o que é desta tela: o rodapé com baixar,
/// imprimir e cancelar.
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
          'para as duas partes. A numeração não é reaproveitada, e o '
          'pagamento continua no extrato: cancelar a nota não estorna dinheiro.',
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
                NfseView(nota: _nota, rodape: _rodape()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rodape() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AcoesDocumento(documento: DocumentoFiscal.daNota(_nota)),
        // Só o prestador cancela — é dele o documento.
        if (!_nota.cancelada && _nota.souPrestador) ...[
          const SizedBox(height: 6),
          _buildBotaoCancelar(),
        ],
      ],
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
}
