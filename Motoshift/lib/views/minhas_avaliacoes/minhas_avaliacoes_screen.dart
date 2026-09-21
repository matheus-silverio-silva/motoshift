import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../avaliacao/avaliacao_screen.dart';
import '../avaliar_entregadores/avaliar_entregadores_screen.dart';

/// Central de avaliações — as recebidas e as que ainda faltam dar.
///
/// Antes esta tela só listava as notas recebidas, e dar uma avaliação
/// dependia de achar o turno no histórico. Para o lojista era pior: não havia
/// entrada nenhuma no menu, e a tela `/avaliar-entregadores` existia sem que
/// nada no aplicativo navegasse até ela.
class MinhasAvaliacoesScreen extends StatefulWidget {
  const MinhasAvaliacoesScreen({super.key});

  @override
  State<MinhasAvaliacoesScreen> createState() =>
      _MinhasAvaliacoesScreenState();
}

class _MinhasAvaliacoesScreenState extends State<MinhasAvaliacoesScreen> {
  Map<String, dynamic>? _dados;

  /// Turnos concluídos em que este usuário ainda não avaliou ninguém.
  List<Turno> _pendentes = const [];

  bool _carregando = true;
  String? _erro;

  bool get _ehLojista =>
      context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final usuario = auth.usuario;
    final id = usuario?.id;
    if (id == null) return;

    try {
      final data = await api.avaliacoes.buscarAvaliacoes(id);
      final pendentes = await _carregarPendentes(api, usuario!, id);
      if (mounted) {
        setState(() {
          _dados = data;
          _pendentes = pendentes;
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

  /// Mesma regra do histórico: turno finalizado cuja avaliação este usuário
  /// ainda não registrou. Cancelado e expirado ficam de fora — não houve
  /// serviço para avaliar.
  Future<List<Turno>> _carregarPendentes(
      ApiService api, Usuario usuario, int id) async {
    final lojista = usuario.tipo == TipoUsuario.lojista;
    final turnos = lojista
        ? await api.turnos.listarTurnosLojista(id)
        : await api.turnos.listarMeusTurnos(id);
    final avaliados = (await api.avaliacoes.buscarTurnosAvaliados(id)).toSet();

    final lista = turnos
        .where((t) =>
            t.status == StatusTurno.finalizado &&
            t.id != null &&
            !avaliados.contains(t.id) &&
            (lojista || t.lojistId > 0))
        .toList()
      ..sort((a, b) => b.dataInicio.compareTo(a.dataInicio));
    return lista;
  }

  /// O lojista de um turno multi-vaga avalia um entregador por vez, então vai
  /// para a tela dedicada; o entregador avalia uma loja só.
  Future<void> _avaliar(Turno turno) async {
    final auth = context.read<AuthService>();
    final avaliadorId = auth.usuario?.id;
    if (avaliadorId == null || turno.id == null) return;

    if (_ehLojista) {
      await Navigator.pushNamed(
        context,
        AppRoutes.avaliarEntregadores,
        arguments: AvaliarEntregadoresArgs(
          turnoId: turno.id!,
          tituloTurno: turno.titulo,
        ),
      );
    } else {
      await Navigator.pushNamed(
        context,
        AppRoutes.avaliacao,
        arguments: AvaliacaoArgs(
          turnoId: turno.id!,
          avaliadorId: avaliadorId,
          avaliadoId: turno.lojistId,
          nomeAvaliado: turno.titulo,
        ),
      );
    }
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final media = (_dados?['mediaGeral'] as num?)?.toDouble() ?? 0.0;
    final total = (_dados?['totalAvaliacoes'] as num?)?.toInt() ?? 0;

    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Avaliações'),
      desktopTitle: 'Avaliações',
      desktopSubtitle: _carregando ? 'Carregando…' : _subtitulo(total, media),
      rotaDaSecao: AppRoutes.minhasAvaliacoes,
      desktopBody: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : _erro != null
              ? _buildErro()
              : _buildDesktop(),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : _erro != null
              ? _buildErro()
              : _buildConteudo(),
    );
  }

  /// Subtítulo que junta as duas metades da tela: quantas notas eu recebi e
  /// quantas eu ainda devo. A pendência vem primeiro — é a que pede ação.
  String _subtitulo(int total, double media) {
    final partes = <String>[
      if (_pendentes.isNotEmpty)
        _pendentes.length == 1
            ? '1 turno a avaliar'
            : '${_pendentes.length} turnos a avaliar',
      if (total == 0)
        'nenhuma avaliação recebida'
      else
        '$total ${total == 1 ? 'avaliação recebida' : 'avaliações recebidas'} · '
            'média ${media.toStringAsFixed(1)}',
    ];
    final texto = partes.join(' · ');
    return texto[0].toUpperCase() + texto.substring(1);
  }

  // ── Desktop — resumo à esquerda, comentários à direita ───────────────────

  Widget _buildDesktop() {
    final media = (_dados?['mediaGeral'] as num?)?.toDouble() ?? 0.0;
    final total = (_dados?['totalAvaliacoes'] as num?)?.toInt() ?? 0;
    final dist =
        Map<String, dynamic>.from((_dados?['distribuicao'] as Map?) ?? {});
    final avaliacoes = (_dados?['avaliacoes'] as List?) ?? const [];

    if (total == 0) return _buildConteudo();

    return ContentGrid(
      children: [
        if (_pendentes.isNotEmpty)
          GridCol(span: 12, child: _buildPendentes()),
        GridCol(
          span: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResumo(media, total),
              const SizedBox(height: 16),
              _buildDistribuicao(dist, total),
            ],
          ),
        ),
        GridCol(
          span: 8,
          child: PanelCard(
            title: 'Comentários recentes',
            padding: const EdgeInsets.all(22),
            gap: 14,
            child: avaliacoes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('Nenhum comentário ainda.',
                          style: tsJakarta(12.5, FontWeight.w400,
                              color: AppColors.muted)),
                    ),
                  )
                : Column(
                    children: avaliacoes
                        .map((a) => _buildAvaliacaoCard(
                            Map<String, dynamic>.from(a as Map)))
                        .toList(),
                  ),
          ),
        ),
      ],
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

    // Sem nota recebida e sem pendência: aí sim a tela está vazia de verdade.
    // Antes bastava `total == 0` para cair aqui, e as avaliações que o usuário
    // devia sumiam junto com as que ele não tinha recebido.
    if (total == 0 && _pendentes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
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
        if (_pendentes.isNotEmpty) ...[
          _buildPendentes(),
          const SizedBox(height: 20),
        ],
        if (total > 0) ...[
          _buildResumo(media, total),
          const SizedBox(height: 16),
          _buildDistribuicao(dist, total),
          const SizedBox(height: 22),
          Text('Comentários recentes',
              style: tsBricolage(14, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 12),
          ...avaliacoes.map((a) =>
              _buildAvaliacaoCard(Map<String, dynamic>.from(a as Map))),
        ],
      ],
    );
  }

  /// Bloco "a avaliar". Fica no topo porque é a única parte da tela que pede
  /// uma ação; o resto é leitura.
  Widget _buildPendentes() {
    final alvo = _ehLojista ? 'entregador' : 'lojista';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.rate_review_outlined,
                  size: 17, color: AppColors.amber),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _pendentes.length == 1
                      ? '1 turno esperando sua avaliação'
                      : '${_pendentes.length} turnos esperando sua avaliação',
                  style:
                      tsBricolage(14, FontWeight.w800, color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Avalie o $alvo de cada turno concluído — a nota entra na '
            'reputação dos dois lados.',
            style: tsJakarta(11.5, FontWeight.w400, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          for (final turno in _pendentes) _buildPendenteRow(turno),
        ],
      ),
    );
  }

  Widget _buildPendenteRow(Turno turno) {
    final data = DateFormat('dd/MM', 'pt_BR').format(turno.dataInicio);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(turno.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(12.5, FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('$data · ${turno.regiao}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => _avaliar(turno),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.tealSoft,
              foregroundColor: AppColors.tealDeep,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Avaliar',
                style: tsJakarta(12.5, FontWeight.w700,
                    color: AppColors.tealDeep)),
          ),
        ],
      ),
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
