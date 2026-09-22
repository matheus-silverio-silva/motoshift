import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/documento_fiscal.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/documento/acoes_documento.dart';
import '../../widgets/documento/comprovante_view.dart';
import '../../widgets/empty_state.dart';

/// O que a rota `/documento` recebe: o documento pronto (vindo do "Gerar"),
/// ou só o lançamento, para buscar.
class DocumentoFiscalArgs {
  const DocumentoFiscalArgs({this.documento, this.transacaoId})
      : assert(documento != null || transacaoId != null);

  final DocumentoFiscal? documento;
  final int? transacaoId;
}

/// Rota `/documento` — a NFS-e ou o comprovante de um lançamento, com "Baixar
/// PDF" e "Imprimir".
///
/// Sub-página do extrato: empilha, e o menu continua destacando a seção de
/// dinheiro do papel. Tudo SIMULADO, e a tela diz isso antes de qualquer
/// outra coisa — ver [MarcaSimulacao].
class DocumentoFiscalScreen extends StatefulWidget {
  const DocumentoFiscalScreen({super.key});

  @override
  State<DocumentoFiscalScreen> createState() => _DocumentoFiscalScreenState();
}

class _DocumentoFiscalScreenState extends State<DocumentoFiscalScreen> {
  DocumentoFiscal? _documento;
  bool _carregando = false;
  String? _erro;

  DocumentoFiscalArgs? get _args {
    final a = ModalRoute.of(context)?.settings.arguments;
    return a is DocumentoFiscalArgs ? a : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = _args;
      if (args?.documento != null) {
        setState(() => _documento = args!.documento);
      } else {
        _carregar();
      }
    });
  }

  Future<void> _carregar() async {
    final id = _args?.transacaoId;
    if (id == null) {
      setState(() => _erro = 'Nenhum lançamento informado.');
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final d = await context.read<ApiService>().carteira.buscarDocumento(id);
      if (mounted) setState(() => _documento = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível abrir o documento.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _documento?.tipo.titulo ?? 'Documento';
    return AdaptiveScaffold(
      header: AppHeader.back(title: titulo),
      desktopTitle: titulo,
      desktopSubtitle: 'Documento simulado — sem valor fiscal',
      body: _conteudo(),
      desktopBody: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _conteudo(),
        ),
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando || (_documento == null && _erro == null)) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
      );
    }
    if (_erro != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          titulo: 'Documento indisponível',
          subtitulo: _erro,
          acaoLabel: 'Tentar novamente',
          onAcao: _carregar,
        ),
      );
    }
    final d = _documento!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        DocumentoView(documento: d, rodape: AcoesDocumento(documento: d)),
      ],
    );
  }
}
