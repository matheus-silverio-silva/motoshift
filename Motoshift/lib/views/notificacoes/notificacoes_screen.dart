import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/notificacao.dart';
import '../../presentation/providers/notificacao_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/app_topbar.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/empty_state.dart';

/// Tela 17 — central de notificações.
class NotificacoesScreen extends StatefulWidget {
  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen> {
  /// null = todas; 'naoLidas'; ou o prefixo do tipo ('turno', 'pagamento',
  /// 'avaliacao').
  String? _filtro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final id = context.read<AuthService>().usuario?.id;
    if (id == null) return;
    await context.read<NotificacaoProvider>().carregar(id);
  }

  Future<void> _marcarTodas() async {
    final id = context.read<AuthService>().usuario?.id;
    if (id == null) return;
    await context.read<NotificacaoProvider>().marcarTodasLidas(id);
  }

  void _abrir(Notificacao n) {
    context.read<NotificacaoProvider>().marcarLida(n.id);
    // A notificação aponta para um turno, mas só carrega o id — as telas de
    // detalhe recebem o objeto Turno por argumento. Até existir uma rota que
    // busque o turno pelo id, o toque apenas marca como lida.
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificacaoProvider>();

    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Notificações'),
      desktopTitle: 'Notificações',
      desktopSubtitle: provider.carregando
          ? 'Carregando…'
          : provider.naoLidas == 0
              ? 'Tudo em dia'
              : '${provider.naoLidas} não '
                  '${provider.naoLidas == 1 ? 'lida' : 'lidas'}',
      desktopSelectedRoute: AppRoutes.notificacoes,
      desktopNotificationCount: provider.naoLidas,
      desktopPrimaryAction: provider.naoLidas == 0
          ? null
          : TopbarSecondaryButton(
              label: 'Marcar todas como lidas',
              icon: Icons.done_all_rounded,
              onTap: _marcarTodas,
            ),
      desktopBody: _buildDesktop(provider),
      body: _buildMobile(provider),
    );
  }

  // ── Mobile ───────────────────────────────────────────────────────────────

  Widget _buildMobile(NotificacaoProvider provider) {
    if (provider.carregando) return _carregandoView();
    if (provider.erro != null) return _erroView(provider.erro!);

    final lista = provider.notificacoes;
    if (lista.isEmpty) return _vazioView();

    return RefreshIndicator(
      onRefresh: _carregar,
      color: AppColors.teal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (provider.naoLidas > 0) ...[
            GestureDetector(
              onTap: _marcarTodas,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.done_all_rounded,
                        size: 16, color: AppColors.tealDeep),
                    const SizedBox(width: 8),
                    Text('Marcar todas como lidas',
                        style: tsJakarta(12.5, FontWeight.w700,
                            color: AppColors.tealDeep)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ..._agrupadas(lista),
        ],
      ),
    );
  }

  // ── Desktop ──────────────────────────────────────────────────────────────

  Widget _buildDesktop(NotificacaoProvider provider) {
    if (provider.carregando) return _carregandoView();
    if (provider.erro != null) return _erroView(provider.erro!);

    final lista = provider.porTipo(_filtro);

    return ContentGrid(
      children: [
        GridCol(span: 3, child: _buildFiltrosDesktop(provider)),
        GridCol(
          span: 9,
          child: PanelCard(
            padding: const EdgeInsets.all(22),
            gap: 0,
            child: lista.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        provider.notificacoes.isEmpty
                            ? 'Nenhuma notificação ainda.'
                            : 'Nenhuma notificação neste filtro.',
                        style: tsJakarta(12.5, FontWeight.w400,
                            color: AppColors.muted),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _agrupadas(lista),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltrosDesktop(NotificacaoProvider provider) {
    final todas = provider.notificacoes;
    final opcoes = <(String?, String, IconData, int)>[
      (null, 'Todas', Icons.inbox_outlined, todas.length),
      (
        'naoLidas',
        'Não lidas',
        Icons.mark_email_unread_outlined,
        provider.naoLidas
      ),
      (
        'turno',
        'Turnos',
        Icons.local_shipping_outlined,
        todas.where((n) => n.tipo.startsWith('turno')).length
      ),
      (
        'pagamento',
        'Pagamentos',
        Icons.payments_outlined,
        todas.where((n) => n.tipo.startsWith('pagamento')).length
      ),
      (
        'avaliacao',
        'Avaliações',
        Icons.star_outline_rounded,
        todas.where((n) => n.tipo.startsWith('avaliacao')).length
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        children: [
          for (final op in opcoes) ...[
            InkWell(
              onTap: () => setState(() => _filtro = op.$1),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _filtro == op.$1
                      ? AppColors.tealSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(op.$3,
                        size: 19,
                        color: _filtro == op.$1
                            ? AppColors.tealDeep
                            : AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        op.$2,
                        style: tsJakarta(
                          13,
                          _filtro == op.$1
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: _filtro == op.$1
                              ? AppColors.tealDeep
                              : AppColors.muted,
                        ),
                      ),
                    ),
                    if (op.$1 == 'naoLidas' && op.$4 > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${op.$4}',
                            style: tsJakarta(10.5, FontWeight.w800,
                                color: const Color(0xFF3A2603))),
                      )
                    else
                      Text('${op.$4}',
                          style: tsJakarta(12, FontWeight.w700,
                              color: AppColors.muted)),
                  ],
                ),
              ),
            ),
            if (op != opcoes.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  // ── Lista agrupada por dia ───────────────────────────────────────────────

  List<Widget> _agrupadas(List<Notificacao> lista) {
    final widgets = <Widget>[];
    String? grupoAtual;

    for (final n in lista) {
      if (n.grupoDia != grupoAtual) {
        grupoAtual = n.grupoDia;
        widgets.add(Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 18, bottom: 10),
          child: Text(
            grupoAtual,
            style: tsJakarta(11, FontWeight.w800, color: AppColors.muted)
                .copyWith(letterSpacing: 11 * .08),
          ),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _NotificacaoCard(
          notificacao: n,
          onTap: () => _abrir(n),
        ),
      ));
    }
    return widgets;
  }

  // ── Estados ──────────────────────────────────────────────────────────────

  Widget _carregandoView() => const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.teal),
      );

  Widget _erroView(String erro) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 44, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(erro,
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

  Widget _vazioView() => const Padding(
        padding: EdgeInsets.all(24),
        child: EmptyState(
          icon: Icons.notifications_none_rounded,
          titulo: 'Nenhuma notificação',
          subtitulo:
              'Avisos de turno, pagamento e avaliação aparecem aqui.',
        ),
      );
}

// ── Card de notificação ─────────────────────────────────────────────────────

class _NotificacaoCard extends StatelessWidget {
  const _NotificacaoCard({required this.notificacao, this.onTap});

  final Notificacao notificacao;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final estilo = notificacao.estilo;
    final naoLida = !notificacao.lida;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Não lida ganha o fundo do próprio tipo; lida fica branca e neutra.
          color: naoLida ? estilo.fundo : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: naoLida ? estilo.frente.withOpacity(0.3) : AppColors.line,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: naoLida ? AppColors.surface : estilo.fundo,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(estilo.icone, size: 19, color: estilo.frente),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          notificacao.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(13.5, FontWeight.w700,
                              color: AppColors.ink),
                        ),
                      ),
                      if (naoLida) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: estilo.frente,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notificacao.mensagem,
                    style: tsJakarta(12.5, FontWeight.w400,
                        color: naoLida ? estilo.frente : AppColors.muted,
                        height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              notificacao.tempoRelativo,
              style: tsJakarta(11, FontWeight.w400,
                  color: naoLida ? estilo.frente : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
