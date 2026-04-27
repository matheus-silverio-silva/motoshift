import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ScoreAnaliseScreen extends StatelessWidget {
  final double scoreAtual;
  final double scoreAnterior;
  final double variacao;
  final String tendencia;
  final String classificacao;
  final String analise;
  final String ultimaAtualizacao;
  final List<Map<String, dynamic>> eventos;

  const ScoreAnaliseScreen({
    super.key,
    required this.scoreAtual,
    required this.scoreAnterior,
    required this.variacao,
    required this.tendencia,
    required this.classificacao,
    required this.analise,
    required this.ultimaAtualizacao,
    required this.eventos,
  });

  Color get _scoreColor {
    if (scoreAtual >= 4.0) return const Color(0xFF00875A);
    if (scoreAtual >= 2.5) return const Color(0xFFF59E0B);
    return const Color(0xFFBA1A1A);
  }

  IconData get _tendenciaIcon {
    if (tendencia == 'up') return Icons.trending_up_rounded;
    if (tendencia == 'down') return Icons.trending_down_rounded;
    return Icons.trending_flat_rounded;
  }

  Color get _tendenciaColor {
    if (tendencia == 'up') return const Color(0xFF00875A);
    if (tendencia == 'down') return const Color(0xFFBA1A1A);
    return AppColors.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Análise de Score',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () => _mostrarRegras(context),
            icon: const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.primary),
            label: const Text(
              'Regras',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildScoreHero(),
            const SizedBox(height: 20),
            _buildProgressBar(),
            const SizedBox(height: 20),
            _buildTendenciaRow(),
            const SizedBox(height: 24),
            _buildAnaliseCard(),
            if (eventos.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildEventosSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _scoreColor.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        children: [
          const Text(
            'SEU SCORE ATUAL',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            scoreAtual.toStringAsFixed(2),
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 72,
              fontWeight: FontWeight.w900,
              letterSpacing: -3,
              color: _scoreColor,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '/ 5.0',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _scoreColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              classificacao,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _scoreColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Progresso do score',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            Text(
              '${(scoreAtual / 5.0 * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (scoreAtual / 5.0).clamp(0.0, 1.0),
            minHeight: 12,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(_scoreColor),
          ),
        ),
      ],
    );
  }

  Widget _buildTendenciaRow() {
    final variacaoStr = variacao == 0
        ? 'Sem variação'
        : (variacao > 0
            ? '+${variacao.abs().toStringAsFixed(1)} pontos'
            : '−${variacao.abs().toStringAsFixed(1)} pontos');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(_tendenciaIcon, color: _tendenciaColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Variação em 30 dias',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  variacaoStr,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _tendenciaColor,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Estimativa anterior',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                scoreAnterior.toStringAsFixed(2),
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnaliseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Análise por IA',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                ultimaAtualizacao,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            analise,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              height: 1.7,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Histórico recente',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...eventos.map((e) => _buildEventoItem(e)),
      ],
    );
  }

  Widget _buildEventoItem(Map<String, dynamic> evento) {
    final tipo = evento['tipo'] as String? ?? 'finalizado';
    final impacto = (evento['impacto'] as num?)?.toDouble() ?? 0.0;
    final titulo = evento['titulo'] as String? ?? '';
    final data = evento['data'] as String? ?? '';

    final IconData icon;
    final Color iconColor;
    final Color bgColor;
    final String impactoStr;

    switch (tipo) {
      case 'finalizado':
        icon = Icons.check_circle_rounded;
        iconColor = const Color(0xFF00875A);
        bgColor = const Color(0xFFECFDF5);
        impactoStr = '+0';
        break;
      case 'cancelado_tardio':
        icon = Icons.cancel_rounded;
        iconColor = const Color(0xFFBA1A1A);
        bgColor = const Color(0xFFFFF1F2);
        impactoStr = '−0.5';
        break;
      default:
        icon = Icons.remove_circle_outline_rounded;
        iconColor = AppColors.onSurfaceVariant;
        bgColor = AppColors.surfaceContainerHigh;
        impactoStr = '0';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  data,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            impactoStr,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: impacto < 0
                  ? const Color(0xFFBA1A1A)
                  : AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarRegras(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Regras de Score',
          style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w800),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RegraItem(emoji: '🏁', texto: 'Score inicial ao se cadastrar: 5.0'),
            SizedBox(height: 10),
            _RegraItem(
                emoji: '⚠️',
                texto: 'Cancelamento com menos de 1h de antecedência: −0.5'),
            SizedBox(height: 10),
            _RegraItem(
                emoji: '✅', texto: 'Concluir turnos: sem impacto no score'),
            SizedBox(height: 16),
            Text(
              'Classificações:',
              style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            SizedBox(height: 8),
            _RegraItem(emoji: '🟢', texto: '4.5 – 5.0  →  Excelente'),
            _RegraItem(emoji: '🔵', texto: '3.5 – 4.4  →  Bom'),
            _RegraItem(emoji: '🟡', texto: '2.5 – 3.4  →  Regular'),
            _RegraItem(emoji: '🔴', texto: '0.0 – 2.4  →  Baixo'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Entendido',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegraItem extends StatelessWidget {
  final String emoji;
  final String texto;

  const _RegraItem({required this.emoji, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
