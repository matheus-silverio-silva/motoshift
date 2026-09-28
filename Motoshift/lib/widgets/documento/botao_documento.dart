import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transacao.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../views/documento_fiscal/documento_fiscal_screen.dart';

/// Abre o documento do lançamento, gerando-o antes quando é de quem olha gerar.
///
/// Para o lojista e para os comprovantes, "gerar" e "ver" são o mesmo pedido:
/// a emissão é idempotente, então a nota já emitida volta como estava, e o
/// comprovante sai sempre igual. A NFS-e do entregador é a exceção: quem emite
/// é o lojista, então o entregador só CONSULTA (GET) — nunca pede a emissão.
/// Um caminho só para o detalhe do lançamento e para a linha do extrato.
Future<void> abrirDocumentoDoLancamento(
    BuildContext context, Transacao lancamento) async {
  final id = lancamento.id;
  if (id == null) return;
  if (lancamento.aguardandoEmissao) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(AvisoAguardandoEmissao.titulo),
    ));
    return;
  }
  try {
    final carteira = context.read<ApiService>().carteira;
    final documento = lancamento.notaDoPrestador
        ? await carteira.buscarDocumento(id)
        : await carteira.gerarDocumento(id);
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
///
/// Para o entregador, a nota que o lojista ainda não emitiu não tem botão:
/// no lugar dele fica o [AvisoAguardandoEmissao].
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
    if (l.aguardandoEmissao) return const AvisoAguardandoEmissao();
    if (!l.documentoDisponivel || tipo == null) return const SizedBox.shrink();

    final rotulo = l.documentoEmitido ? 'Ver nota fiscal' : tipo.acao;
    return FilledButton.icon(
      key: const Key('lancamento-gerar-documento'),
      onPressed: _gerando
          ? null
          : () async {
              setState(() => _gerando = true);
              await abrirDocumentoDoLancamento(context, l);
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

/// A nota do entregador que o lojista ainda não emitiu: informação, não
/// tarefa. Sem botão, porque não há nada que o entregador possa fazer — a
/// notificação avisa quando a nota sair.
class AvisoAguardandoEmissao extends StatelessWidget {
  const AvisoAguardandoEmissao({super.key});

  static const titulo = 'Aguardando emissão pelo lojista';

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('lancamento-aguardando-emissao'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo,
                    style: tsJakarta(12.5, FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  'A NFS-e deste pagamento é emitida pela loja. Você recebe um '
                  'aviso quando ela sair, e ela aparece em Notas fiscais.',
                  style: tsJakarta(11, FontWeight.w400,
                      color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
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
