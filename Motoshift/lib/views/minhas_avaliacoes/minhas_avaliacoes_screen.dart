import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';

class MinhasAvaliacoesScreen extends StatefulWidget {
  const MinhasAvaliacoesScreen({super.key});

  @override
  State<MinhasAvaliacoesScreen> createState() =>
      _MinhasAvaliacoesScreenState();
}

class _MinhasAvaliacoesScreenState extends State<MinhasAvaliacoesScreen> {
  Map<String, dynamic>? _dados;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    try {
      final data = await api.buscarAvaliacoes(id);
      if (mounted) {
        setState(() {
          _dados = data;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível carregar suas avaliações.';
          _carregando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      header: AppHeader.back(title: 'Minhas avaliações'),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : _erro != null
              ? _buildErro()
              : _buildConteudo(),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.muted, size: 44),
            const SizedBox(height: 10),
            Text(_erro!,
                textAlign: TextAlign.center,
                style: tsJakarta(13, FontWeight.w400,
                    color: AppColors.muted)),
            const SizedBox(height: 14),
            TextButton(
                onPressed: () {
                  setState(() {
                    _carregando = true;
                    _erro = null;
                  });
                  _carregar();
                },
                child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    final media = (_dados?['mediaGeral'] as num?)?.toDouble() ?? 0.0;
    final total = (_dados?['totalAvaliacoes'] as num?)?.toInt() ?? 0;
    final dist = Map<String, dynamic>.from(
        (_dados?['distribuicao'] as Map?) ?? {});
    final avaliacoes =
        (_dados?['avaliacoes'] as List?) ?? const [];

    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_outline_rounded,
                    color: AppColors.teal, size: 32),
              ),
              const SizedBox(height: 14),
              Text('Sem avaliações ainda',
                  style: tsBricolage(16, FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 4),
              Text(
                'Suas avaliações aparecem aqui após cada turno concluído.',
                textAlign: TextAlign.center,
                style: tsJakarta(12, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
      children: [
        _buildResumo(media, total),
        const SizedBox(height: 16),
        _buildDistribuicao(dist, total),
        const SizedBox(height: 22),
        Text('Comentários recentes',
            style:
                tsBricolage(14, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 12),
        ...avaliacoes.map((a) => _buildAvaliacaoCard(
            Map<String, dynamic>.from(a as Map))),
      ],
    );
  }

  Widget _buildResumo(double media, int total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(media.toStringAsFixed(1),
                    style: tsBricolage(36, FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = (i + 1) <= media.round();
                    return Icon(
                      filled
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 15,
                      color: Colors.white,
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total de avaliações',
                    style: tsJakarta(10, FontWeight.w600,
                        color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$total',
                      style: tsBricolage(24, FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistribuicao(Map<String, dynamic> dist, int total) {
    const labels = [
      ('5estrelas', 5),
      ('4estrelas', 4),
      ('3estrelas', 3),
      ('2estrelas', 2),
      ('1estrela', 1),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        children: labels.map((l) {
          final count = (dist[l.$1] as num?)?.toInt() ?? 0;
          final pct = total > 0 ? count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Row(
                    children: [
                      Text('${l.$2}',
                          style: tsJakarta(11, FontWeight.w700,
                              color: AppColors.ink)),
                      const Icon(Icons.star_rounded,
                          size: 11, color: AppColors.amber),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: AppColors.surface3,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.teal),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 22,
                  child: Text('$count',
                      textAlign: TextAlign.right,
                      style: tsJakarta(10, FontWeight.w700,
                          color: AppColors.muted)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAvaliacaoCard(Map<String, dynamic> a) {
    final nota = (a['nota'] as num?)?.toInt() ?? 0;
    final nome = a['nomeAvaliador'] as String? ?? 'Usuário';
    final comentario = a['comentario'] as String?;
    final dataStr = a['data'] as String?;
    String dataFmt = '';
    if (dataStr != null) {
      try {
        dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR')
            .format(DateTime.parse(dataStr));
      } catch (_) {}
    }
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(initials,
                      style: tsBricolage(12, FontWeight.w800,
                          color: AppColors.tealDeep)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nome,
                        style: tsJakarta(12.5, FontWeight.w700,
                            color: AppColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (dataFmt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(dataFmt,
                          style: tsJakarta(10, FontWeight.w400,
                              color: AppColors.muted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < nota;
                  return Icon(
                    filled
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 12,
                    color:
                        filled ? AppColors.amber : AppColors.line,
                  );
                }),
              ),
            ],
          ),
          if (comentario != null && comentario.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comentario,
                style: tsJakarta(12, FontWeight.w400,
                    color: AppColors.text, height: 1.5)),
          ],
        ],
      ),
    );
  }
}
