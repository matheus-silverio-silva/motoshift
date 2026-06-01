import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
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
        if (_comentarioCtrl.text.trim().isNotEmpty)
          'comentario': _comentarioCtrl.text.trim(),
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

    return AppScaffold(
      header: AppHeader.back(title: 'Avaliação'),
      body: ListView(
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
      ),
    );
  }
}
