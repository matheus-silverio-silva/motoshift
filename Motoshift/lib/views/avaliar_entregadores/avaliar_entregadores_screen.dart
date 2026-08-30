import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/rating_stars.dart';

/// Argumentos da rota `/avaliar-entregadores`.
class AvaliarEntregadoresArgs {
  const AvaliarEntregadoresArgs({
    required this.turnoId,
    required this.tituloTurno,
  });

  final int turnoId;
  final String tituloTurno;
}

/// Um entregador pendente de avaliação e a nota que o lojista já escolheu.
class _Pendente {
  _Pendente({required this.usuarioId, required this.nome});

  final int usuarioId;
  final String nome;

  int nota = 0;
  final comentario = TextEditingController();
  bool enviado = false;
  bool enviando = false;

  String get iniciais {
    final partes = nome.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes.last[0]).toUpperCase();
  }
}

/// Tela 19 — avaliar vários entregadores do mesmo turno.
///
/// Um turno multi-vaga tem um entregador por vaga, e cada um recebe a própria
/// avaliação: um POST por entregador, com o `avaliadoId` correspondente.
class AvaliarEntregadoresScreen extends StatefulWidget {
  const AvaliarEntregadoresScreen({super.key});

  @override
  State<AvaliarEntregadoresScreen> createState() =>
      _AvaliarEntregadoresScreenState();
}

class _AvaliarEntregadoresScreenState
    extends State<AvaliarEntregadoresScreen> {
  List<_Pendente> _pendentes = [];
  bool _carregando = true;
  String? _erro;

  /// Quantos já estavam avaliados quando a tela abriu.
  ///
  /// O endpoint devolve só os pendentes — não diz quantos entregadores o turno
  /// tem no total. Sem esse dado o progresso é contado sobre os pendentes que
  /// chegaram, então "2 de 3" significa "2 dos 3 que faltavam".
  final int _jaAvaliados = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void dispose() {
    for (final p in _pendentes) {
      p.comentario.dispose();
    }
    super.dispose();
  }

  AvaliarEntregadoresArgs? get _args =>
      ModalRoute.of(context)?.settings.arguments
          as AvaliarEntregadoresArgs?;

  Future<void> _carregar() async {
    final args = _args;
    final usuarioId = context.read<AuthService>().usuario?.id;
    if (args == null || usuarioId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Turno não informado.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final api = context.read<ApiService>();
      final resp =
          await api.avaliacoes.buscarAvaliacoesPendentes(args.turnoId, usuarioId);
      if (!mounted) return;
      setState(() {
        _pendentes = resp.pendentes
            .map((p) => _Pendente(
                  usuarioId: (p['usuarioId'] as num).toInt(),
                  nome: p['nome'] as String? ?? 'Entregador',
                ))
            .toList();
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar os entregadores deste turno.';
      });
    }
  }

  int get _avaliadosAgora => _pendentes.where((p) => p.enviado).length;
  int get _total => _jaAvaliados + _pendentes.length;
  int get _concluidos => _jaAvaliados + _avaliadosAgora;

  Future<void> _enviar(_Pendente p) async {
    final args = _args;
    final avaliadorId = context.read<AuthService>().usuario?.id;
    if (args == null || avaliadorId == null || p.nota == 0) return;

    setState(() => p.enviando = true);
    try {
      final api = context.read<ApiService>();
      await api.avaliacoes.registrarAvaliacao({
        'turnoId': args.turnoId,
        'avaliadorId': avaliadorId,
        // Cada envio carrega o id do entregador daquele card — é o ponto
        // inteiro desta tela.
        'avaliadoId': p.usuarioId,
        'nota': p.nota,
        if (p.comentario.text.trim().isNotEmpty)
          'comentario': p.comentario.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        p.enviado = true;
        p.enviando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.nome} avaliado.'),
          backgroundColor: AppColors.good,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => p.enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao enviar a avaliação. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;

    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Avaliar entregadores'),
      desktopTitle: 'Avaliar entregadores',
      desktopSubtitle: args?.tituloTurno ?? 'Turno',
      desktopSelectedRoute: AppRoutes.turnosLojista,
      desktopBody: _buildConteudo(desktop: true),
      body: _buildConteudo(desktop: false),
    );
  }

  Widget _buildConteudo({required bool desktop}) {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.teal),
      );
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 44, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(_erro!,
                  textAlign: TextAlign.center,
                  style: tsJakarta(13, FontWeight.w400,
                      color: AppColors.muted)),
              const SizedBox(height: 14),
              TextButton(
                  onPressed: _carregar,
                  child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }
    if (_pendentes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: EmptyState(
          icon: Icons.done_all_rounded,
          titulo: 'Nada a avaliar',
          subtitulo:
              'Todos os entregadores deste turno já foram avaliados.',
        ),
      );
    }

    if (desktop) {
      return ContentGrid(
        children: [
          GridCol(span: 12, child: _buildProgresso()),
          for (final p in _pendentes)
            GridCol(span: 6, child: _buildCard(p)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _buildProgresso(),
        const SizedBox(height: 16),
        for (final p in _pendentes) ...[
          _buildCard(p),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildProgresso() {
    final progresso = _total == 0 ? 0.0 : _concluidos / _total;

    return PanelCard(
      padding: const EdgeInsets.all(18),
      gap: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Progresso',
                  style:
                      tsBricolage(15, FontWeight.w800, color: AppColors.ink),
                ),
              ),
              Text(
                '$_concluidos de $_total ${_total == 1 ? 'avaliado' : 'avaliados'}',
                style:
                    tsJakarta(12.5, FontWeight.w700, color: AppColors.tealDeep),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 8,
              backgroundColor: AppColors.surface3,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.teal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_Pendente p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.enviado ? AppColors.good.withOpacity(0.4) : AppColors.line,
          width: 1.5,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient:
                      p.enviado ? null : AppColors.primaryGradient,
                  color: p.enviado ? AppColors.goodSoft : null,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: p.enviado
                      ? const Icon(Icons.check_rounded,
                          color: Color(0xFF0F6E4E), size: 22)
                      : Text(p.iniciais,
                          style: tsBricolage(15, FontWeight.w800,
                              color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(13.5, FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      p.enviado ? 'Avaliação enviada' : 'Aguardando avaliação',
                      style: tsJakarta(11.5, FontWeight.w400,
                          color: p.enviado
                              ? const Color(0xFF0F6E4E)
                              : AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!p.enviado) ...[
            const SizedBox(height: 14),
            Center(
              child: RatingStars(
                rating: p.nota,
                onRatingChanged: (r) => setState(() => p.nota = r),
                size: 30,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: p.comentario,
                maxLength: 100,
                maxLines: 2,
                style: tsJakarta(12.5, FontWeight.w400),
                decoration: InputDecoration(
                  hintText: 'Comentário (opcional)…',
                  hintStyle: tsJakarta(12.5, FontWeight.w400,
                      color: AppColors.muted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  counterStyle: tsJakarta(9, FontWeight.w400,
                      color: AppColors.muted),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Enviar avaliação',
              loading: p.enviando,
              onPressed: p.nota > 0 ? () => _enviar(p) : null,
            ),
          ],
        ],
      ),
    );
  }
}
