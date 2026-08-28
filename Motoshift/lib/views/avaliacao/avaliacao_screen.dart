import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/rating_stars.dart';

/// Route arguments: AvaliacaoArgs
class AvaliacaoArgs {
  final int turnoId;
  final int avaliadorId;
  final int avaliadoId;
  final String nomeAvaliado;

  const AvaliacaoArgs({
    required this.turnoId,
    required this.avaliadorId,
    required this.avaliadoId,
    required this.nomeAvaliado,
  });
}

class AvaliacaoScreen extends StatefulWidget {
  const AvaliacaoScreen({super.key});

  @override
  State<AvaliacaoScreen> createState() => _AvaliacaoScreenState();
}

class _AvaliacaoScreenState extends State<AvaliacaoScreen> {
  int _nota = 0;
  final _comentarioCtrl = TextEditingController();
  bool _enviando = false;

  static const _tags = [
    'Pontual', 'Organizado', 'Boa comunicação',
    'Carga bem embalada', 'Pagamento correto',
  ];
  final Set<String> _tagsSelected = {};

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  /// Combina as tags selecionadas (pontos positivos) com o comentário livre num
  /// único texto, respeitando o limite de 100 caracteres da coluna `comentario`
  /// no backend. Formato: "Pontual • Organizado — comentário livre".
  String _montarComentario() {
    const max = 100;
    final tags = _tagsSelected.join(' • ');
    final texto = _comentarioCtrl.text.trim();

    String resultado;
    if (tags.isNotEmpty && texto.isNotEmpty) {
      resultado = '$tags — $texto';
    } else {
      resultado = tags.isNotEmpty ? tags : texto;
    }

    return resultado.length > max ? resultado.substring(0, max) : resultado;
  }

  Future<void> _enviar(AvaliacaoArgs args) async {
    if (_nota == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma nota antes de enviar.')),
      );
      return;
    }
    setState(() => _enviando = true);
    final api = context.read<ApiService>();
    try {
      await api.registrarAvaliacao({
        'turnoId': args.turnoId,
        'avaliadorId': args.avaliadorId,
        'avaliadoId': args.avaliadoId,
        'nota': _nota,
        if (_montarComentario().isNotEmpty)
          'comentario': _montarComentario(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação enviada com sucesso!'),
          backgroundColor: AppColors.good,
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao enviar avaliação. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as AvaliacaoArgs?;

    if (context.isDesktop) return _buildModalDesktop(args);

    return AppScaffold(
      header: AppHeader.back(title: 'Avaliação'),
      body: _buildFormulario(args),
    );
  }

  /// No desktop a avaliação é um modal de 480px sobre um fundo escurecido,
  /// conforme o artboard 12.
  ///
  /// A rota continua opaca, então a tela de origem não aparece por trás — um
  /// overlay de verdade exigiria trocar `routes:` por uma rota transparente
  /// em app.dart.
  Widget _buildModalDesktop(AvaliacaoArgs? args) {
    return Scaffold(
      backgroundColor: AppColors.ink.withOpacity(0.45),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(22, 16, 12, 16),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      bottom:
                          BorderSide(color: AppColors.line, width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Avaliação',
                            style: tsBricolage(17, FontWeight.w800,
                                color: AppColors.ink)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: AppColors.muted),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                Flexible(child: _buildFormulario(args)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormulario(AvaliacaoArgs? args) {
    return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          // Avatar + nome avaliado
          Center(
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      args?.nomeAvaliado.isNotEmpty == true
                          ? args!.nomeAvaliado[0].toUpperCase()
                          : '?',
                      style: tsBricolage(24, FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  args?.nomeAvaliado ?? 'Usuário',
                  style:
                      tsBricolage(16, FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  'Como foi sua experiência neste turno?',
                  style: tsJakarta(12, FontWeight.w400,
                      color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Estrelas
          Center(
            child: RatingStars(
              rating: _nota,
              onRatingChanged: (r) => setState(() => _nota = r),
              size: 38,
            ),
          ),
          const SizedBox(height: 20),
          // Tags de qualidade
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pontos positivos',
                    style: tsJakarta(11, FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) {
                    final sel = _tagsSelected.contains(tag);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) _tagsSelected.remove(tag);
                        else _tagsSelected.add(tag);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.teal : AppColors.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: sel
                                ? AppColors.teal
                                : AppColors.line,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: tsJakarta(11, FontWeight.w700,
                              color: sel
                                  ? Colors.white
                                  : AppColors.muted),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Comentário
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _comentarioCtrl,
              maxLength: 200,
              maxLines: 3,
              style: tsJakarta(13, FontWeight.w400),
              decoration: InputDecoration(
                hintText: 'Comentário adicional (opcional)...',
                hintStyle: tsJakarta(13, FontWeight.w400,
                    color: AppColors.muted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                counterStyle: tsJakarta(9, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Enviar avaliação',
            loading: _enviando,
            onPressed: args != null ? () => _enviar(args) : null,
          ),
          const SizedBox(height: 10),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Text(
                'Pular por enquanto',
                style: tsJakarta(12, FontWeight.w600,
                    color: AppColors.muted),
              ),
            ),
          ),
        ],
      );
  }
}
