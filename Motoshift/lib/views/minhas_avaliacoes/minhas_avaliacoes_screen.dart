import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../presentation/providers/pendencias_provider.dart';
import '../../routes/abrir_avaliacao.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/empty_state.dart';

/// As duas abas de uma avaliação: a que eu recebi e a que eu devo.
enum _Aba { aAvaliar, recebidas }

/// Central de avaliações — as recebidas e as que ainda faltam dar.
///
/// Antes esta tela só listava as notas recebidas, e dar uma avaliação
/// dependia de achar o turno no histórico. Para o lojista era pior: não havia
/// entrada nenhuma no menu, e a tela `/avaliar-entregadores` existia sem que
/// nada no aplicativo navegasse até ela.
///
/// As duas metades viraram abas porque respondem a perguntas diferentes —
/// "como estou indo?" e "o que eu devo?" — e, empilhadas, a segunda ficava
/// abaixo da dobra justamente quando havia o que fazer. A aba inicial é "A
/// avaliar" quando há pendência, e "Recebidas" quando não há.
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

  /// Aba escolhida pela pessoa. Enquanto for `null` a tela decide sozinha,
  /// pela existência de pendência; depois do primeiro toque, manda o toque.
  _Aba? _abaEscolhida;

  bool get _ehLojista =>
      context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;

  /// A metade "a avaliar" vem do PendenciasProvider, a mesma fonte do painel
  /// do início e do selo do menu. Esta tela contava sozinha, por
  /// `/avaliacoes/feitas`, e discordava das outras no turno multi-vaga.
  List<TurnoAAvaliar> get _pendentes =>
      context.watch<PendenciasProvider>().turnosAAvaliar;

  _Aba get _aba =>
      _abaEscolhida ?? (_pendentes.isEmpty ? _Aba.recebidas : _Aba.aAvaliar);

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

    final pendencias = context.read<PendenciasProvider>();
    try {
      final data = await api.avaliacoes.buscarAvaliacoes(id);
      await pendencias.carregar(usuario);
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

  /// Abre a avaliação do turno — a tela por entregador para o lojista, a da
  /// loja para o entregador. Quem decide é [abrirAvaliacao], para que os
  /// cinco lugares de onde se avalia levem ao mesmo destino e mostrem o mesmo
  /// nome.
  Future<void> _avaliar(TurnoAAvaliar pendente) async {
    await abrirAvaliacao(context, pendente.turno);
    if (mounted) _carregar();
  }

  /// Seletor das duas abas.
  Widget _buildAbas() {
    final quantas = context.watch<PendenciasProvider>().quantidadeAvaliacoes;
    return Row(
      children: [
        _abaBotao(_Aba.aAvaliar,
            quantas == 0 ? 'A avaliar' : 'A avaliar ($quantas)'),
        const SizedBox(width: 8),
        _abaBotao(_Aba.recebidas, 'Recebidas'),
      ],
    );
  }

  Widget _abaBotao(_Aba aba, String rotulo) {
    final sel = _aba == aba;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _abaEscolhida = aba),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppColors.teal : AppColors.surface2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            rotulo,
            style: tsJakarta(12.5, FontWeight.w700,
                color: sel ? Colors.white : AppColors.muted),
          ),
        ),
      ),
    );
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
    final aFazer = context.watch<PendenciasProvider>().quantidadeAvaliacoes;
    final partes = <String>[
      if (aFazer > 0)
        aFazer == 1 ? '1 avaliação a fazer' : '$aFazer avaliações a fazer',
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

    return ContentGrid(
      children: [
        GridCol(span: 12, child: _buildAbas()),
        if (_aba == _Aba.aAvaliar)
          GridCol(span: 12, child: _aAvaliar())
        else if (total == 0)
          GridCol(span: 12, child: _semRecebidas())
        else ...[
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
      ],
    );
  }

  /// A aba "A avaliar" — o bloco de pendências, ou o vazio que explica por que
  /// não há nada.
  Widget _aAvaliar() {
    if (_pendentes.isNotEmpty) return _buildPendentes();
    return EmptyState(
      icon: Icons.task_alt_rounded,
      titulo: 'Nada para avaliar',
      subtitulo: _ehLojista
          ? 'Quando um turno seu for concluído, o entregador aparece aqui '
              'para receber a nota.'
          : 'Quando você concluir um turno, a loja aparece aqui para '
              'receber a nota.',
    );
  }

  Widget _semRecebidas() {
    return const EmptyState(
      icon: Icons.star_outline_rounded,
      titulo: 'Sem avaliações ainda',
      subtitulo: 'Suas avaliações aparecem aqui após cada turno concluído.',
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          titulo: 'Não foi possível carregar',
          subtitulo: _erro,
          acaoLabel: 'Tentar novamente',
          onAcao: () {
            setState(() {
              _carregando = true;
              _erro = null;
            });
            _carregar();
          },
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    final media = (_dados?['mediaGeral'] as num?)?.toDouble() ?? 0.0;
    final total = (_dados?['totalAvaliacoes'] as num?)?.toInt() ?? 0;
    final dist = Map<String, dynamic>.from(
        (_dados?['distribuicao'] as Map?) ?? {});
    final avaliacoes = (_dados?['avaliacoes'] as List?) ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
      children: [
        _buildAbas(),
        const SizedBox(height: 16),
        if (_aba == _Aba.aAvaliar)
          _aAvaliar()
        else if (total == 0)
          _semRecebidas()
        else ...[
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

  /// Bloco "a avaliar" — uma linha por turno, com quantas notas faltam nele.
  Widget _buildPendentes() {
    final alvo = _ehLojista ? 'entregador' : 'lojista';
    final quantas = context.watch<PendenciasProvider>().quantidadeAvaliacoes;
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
                  quantas == 1
                      ? '1 avaliação esperando você'
                      : '$quantas avaliações esperando você',
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
          for (final pendente in _pendentes) _buildPendenteRow(pendente),
        ],
      ),
    );
  }

  Widget _buildPendenteRow(TurnoAAvaliar pendente) {
    final turno = pendente.turno;
    final data = DateFormat('dd/MM', 'pt_BR').format(turno.dataInicio);

    // O turno multi-vaga tem uma nota por entregador: o subtítulo diz os
    // nomes que faltam, porque "Turno Noite" sozinho não conta quantos são.
    final nomes = pendente.pendentes.map((p) => p.nome).join(', ');
    final detalhe = nomes.isEmpty ? '$data · ${turno.regiao}' : '$data · $nomes';

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
                Text(detalhe,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => _avaliar(pendente),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.tealSoft,
              foregroundColor: AppColors.tealDeep,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
                pendente.pendentes.length > 1
                    ? 'Avaliar (${pendente.pendentes.length})'
                    : 'Avaliar',
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
