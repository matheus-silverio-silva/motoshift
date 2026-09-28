import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tags_de_avaliacao.dart';
import '../../models/usuario.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/rating_stars.dart';
import '../../widgets/seletor_de_gorjeta.dart';

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

  final Set<String> _tagsSelected = {};

  /// Gorjeta opcional (V17) — só quando quem avalia é o lojista.
  double? _gorjeta;

  bool get _souLojista =>
      context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;

  /// Quem avalia é a conta logada; quem é avaliado é o outro lado do turno.
  /// O lojista avalia entregador, o entregador avalia loja — e cada um marca
  /// o que o outro faz ([TagsDeAvaliacao]).
  List<String> get _tags {
    final avaliador = context.read<AuthService>().usuario?.tipo;
    final avaliado = avaliador == TipoUsuario.lojista
        ? TipoUsuario.motoboy
        : TipoUsuario.lojista;
    return TagsDeAvaliacao.para(avaliado);
  }

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
      await api.avaliacoes.registrarAvaliacao({
        'turnoId': args.turnoId,
        'avaliadorId': args.avaliadorId,
        'avaliadoId': args.avaliadoId,
        'nota': _nota,
        if (_montarComentario().isNotEmpty)
          'comentario': _montarComentario(),
      });
      if (!mounted) return;
      final gorjetaFalhou = await _darGorjeta(args);
      if (!mounted) return;
      if (!gorjetaFalhou) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_gorjeta == null
                ? 'Avaliação enviada com sucesso!'
                : 'Avaliação e gorjeta de ${_moeda(_gorjeta!)} enviadas!'),
            backgroundColor: AppColors.good,
          ),
        );
      }
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

  /// Dá a gorjeta depois da avaliação. A avaliação já foi: se a gorjeta
  /// falhar (sem saldo, por exemplo), diz o porquê — com a mensagem do
  /// backend — em vez de desfazer o que deu certo. Devolve se falhou.
  Future<bool> _darGorjeta(AvaliacaoArgs args) async {
    final valor = _gorjeta;
    if (valor == null || !_souLojista) return false;
    try {
      await context
          .read<ApiService>()
          .turnos
          .darGorjeta(args.turnoId, args.avaliadoId, valor);
      return false;
    } on ApiException catch (e) {
      _avisarGorjeta(e.message);
    } catch (_) {
      _avisarGorjeta('Não foi possível enviar a gorjeta agora.');
    }
    return true;
  }

  void _avisarGorjeta(String motivo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Avaliação enviada, mas a gorjeta não: $motivo'),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 6),
    ));
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).replaceAll('.', ',')}';

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
  /// O escurecido é este `backgroundColor` translúcido, e por muito tempo ele
  /// não escurecia coisa nenhuma: a rota era opaca, então atrás do scrim não
  /// havia nada para aparecer. Quem abre a avaliação agora é
  /// `abrirAvaliacao`, que no desktop empurra uma rota `opaque: false` — a
  /// tela de origem continua na árvore e aparece através daqui.
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
          // Gorjeta: só o lojista, avaliando o entregador.
          if (_souLojista) ...[
            const SizedBox(height: 12),
            SeletorDeGorjeta(onMudou: (v) => _gorjeta = v),
          ],
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
