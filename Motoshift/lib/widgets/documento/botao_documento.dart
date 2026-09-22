import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transacao.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../views/documento_fiscal/documento_fiscal_screen.dart';

/// Gera o documento do lançamento no backend e abre a tela dele.
///
/// "Gerar" e "ver" são o mesmo pedido: a emissão é idempotente, então a nota
/// já emitida volta como estava, e o comprovante sai sempre igual. Um caminho
/// só para o detalhe do lançamento e para a linha do extrato.
Future<void> gerarEAbrirDocumento(BuildContext context, Transacao lancamento) async {
  final id = lancamento.id;
  if (id == null) return;
  try {
    final documento = await context.read<ApiService>().carteira.gerarDocumento(id);
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.documentoFiscal,
      arguments: DocumentoFiscalArgs(documento: documento),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e is ApiException ? e.message : 'Não foi possível gerar o documento.'),
      backgroundColor: AppColors.error,
    ));
  }
}

/// O botão do detalhe do lançamento: "Gerar nota fiscal" ou "Gerar
/// comprovante", ou "Ver nota fiscal" quando ela já foi emitida.
class BotaoDocumento extends StatefulWidget {
  const BotaoDocumento({required this.lancamento, super.key});

  final Transacao lancamento;

  @override
  State<BotaoDocumento> createState() => _BotaoDocumentoState();
}

class _BotaoDocumentoState extends State<BotaoDocumento> {
  bool _gerando = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.lancamento;
    final tipo = l.tipoDocumento;
    if (!l.documentoDisponivel || tipo == null) return const SizedBox.shrink();

    final rotulo = l.documentoEmitido ? 'Ver nota fiscal' : tipo.acao;
    return FilledButton.icon(
      key: const Key('lancamento-gerar-documento'),
      onPressed: _gerando
          ? null
          : () async {
              setState(() => _gerando = true);
              await gerarEAbrirDocumento(context, l);
              if (mounted) setState(() => _gerando = false);
            },
      icon: _gerando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(tipo.ehNota ? Icons.receipt_long_outlined : Icons.description_outlined,
              size: 18),
      label: Text(rotulo, style: tsJakarta(13, FontWeight.w700, color: Colors.white)),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.teal,
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}

/// O selo "NFS-e emitida" — o indicador de documento que o extrato e o
/// detalhe mostram. Comprovante não tem selo: ele não é emitido, é derivado.
class SeloNotaEmitida extends StatelessWidget {
  const SeloNotaEmitida({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Nota fiscal emitida',
      child: Container(
        key: const Key('selo-nota-emitida'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 11, color: AppColors.tealDeep),
            const SizedBox(width: 3),
            Text('NFS-e',
                style: tsJakarta(9.5, FontWeight.w700, color: AppColors.tealDeep)),
          ],
        ),
      ),
    );
  }
}
