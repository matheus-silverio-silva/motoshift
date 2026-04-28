import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class PerfilPublicoScreen extends StatefulWidget {
  final int usuarioId;
  final String nomeUsuario;

  const PerfilPublicoScreen({
    super.key,
    required this.usuarioId,
    required this.nomeUsuario,
  });

  @override
  State<PerfilPublicoScreen> createState() => _PerfilPublicoScreenState();
}

class _PerfilPublicoScreenState extends State<PerfilPublicoScreen> {
  bool _carregando = true;
  Map<String, dynamic>? _data;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final api = context.read<ApiService>();
      final data = await api.buscarPerfilPublico(widget.usuarioId);
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar o perfil.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
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
        title: Text(
          widget.nomeUsuario,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _erro != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.onSurfaceVariant, size: 48),
                      const SizedBox(height: 12),
                      Text(_erro!,
                          style: const TextStyle(
                              fontFamily: 'Manrope',
                              color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      TextButton(
                          onPressed: _carregar,
                          child: const Text('Tentar novamente')),
                    ],
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final media = (_data!['mediaGeral'] as num?)?.toDouble() ?? 0.0;
    final total = (_data!['totalAvaliacoes'] as num?)?.toInt() ?? 0;
    final dist = _data!['distribuicao'] as Map<String, dynamic>? ?? {};
    final avaliacoes =
        (_data!['avaliacoes'] as List<dynamic>).cast<Map<String, dynamic>>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com avatar e rating geral
          _buildHeader(media, total),
          const SizedBox(height: 24),
          // Distribuição de estrelas
          _buildDistribuicao(dist, total),
          const SizedBox(height: 24),
          // Últimas avaliações
          if (avaliacoes.isNotEmpty) ...[
            const Text(
              'Avaliações recentes',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...avaliacoes
                .take(5)
                .map(_buildAvaliacaoCard),
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nenhuma avaliação ainda.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: AppColors.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(double media, int total) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.primaryFixed,
            child: Text(
              widget.nomeUsuario.isNotEmpty
                  ? widget.nomeUsuario[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.onPrimaryFixed,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.nomeUsuario,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ...List.generate(5, (i) {
                      final filled = i < media.floor();
                      final partial = !filled && i < media;
                      return Icon(
                        partial
                            ? Icons.star_half_rounded
                            : filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                        color: const Color(0xFFF59E0B),
                        size: 18,
                      );
                    }),
                    const SizedBox(width: 8),
                    Text(
                      media.toStringAsFixed(1),
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$total avaliação${total != 1 ? 'ões' : ''}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistribuicao(Map<String, dynamic> dist, int total) {
    final items = [
      ('5 estrelas', dist['5estrelas'] as int? ?? 0),
      ('4 estrelas', dist['4estrelas'] as int? ?? 0),
      ('3 estrelas', dist['3estrelas'] as int? ?? 0),
      ('2 estrelas', dist['2estrelas'] as int? ?? 0),
      ('1 estrela', dist['1estrela'] as int? ?? 0),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribuição',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final frac = total > 0 ? item.$2 / total : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      item.$1,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceContainerHighest,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${item.$2}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAvaliacaoCard(Map<String, dynamic> av) {
    final nota = av['nota'] as int;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                av['nomeAvaliador'] as String? ?? 'Usuário',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              Row(
                children: List.generate(
                  nota,
                  (_) => const Icon(Icons.star_rounded,
                      color: Color(0xFFF59E0B), size: 14),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                av['data'] as String? ?? '',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 10,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if ((av['comentario'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              av['comentario'] as String,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                height: 1.4,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
