import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/notificacao_provider.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/serie_diaria.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/app_topbar.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/inline_empty.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/desktop/shift_row.dart';
import '../../widgets/desktop/wallet_kpi_card.dart';
import '../../widgets/desktop/weekly_bar_chart_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/mini_bar_chart.dart';
import '../../widgets/section_title.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_pill.dart';


/// Altura da linha de KPIs do desktop. O card de saldo é o mais alto (tem
/// botão no lugar do subtítulo); no grid do protótipo os demais se esticam
/// até ele, então todos recebem a mesma altura mínima.
const double _alturaKpi = 126;

class DashboardMotoboyScreen extends StatefulWidget {
  const DashboardMotoboyScreen({super.key, this.agora});

  /// Fixa o "agora" da saudação. Só os testes passam isto — ver
  /// [AgendaScreen.agora] para o porquê.
  final DateTime? agora;

  @override
  State<DashboardMotoboyScreen> createState() =>
      _DashboardMotoboyScreenState();
}

class _DashboardMotoboyScreenState extends State<DashboardMotoboyScreen> {
  Map<String, dynamic>? _dashData;

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

    context.read<TurnoProvider>().carregarMeusTurnos(id);
    context.read<NotificacaoProvider>().carregarContagem(id);

    try {
      final data = await api.dashboardMotoboy(id);
      if (mounted) setState(() => _dashData = data);
    } catch (_) {}
  }

  String _greeting() {
    final h = (widget.agora ?? clock.now()).hour;
    if (h < 12) return 'Bom dia,';
    if (h < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  void _onNav(int i) {
    switch (i) {
      case 0:
        break;
      case 1:
        Navigator.pushReplacementNamed(
            context, AppRoutes.turnosDisponiveis);
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.carteira);
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 4.0) return AppColors.good;
    if (score >= 2.5) return AppColors.amber;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Motoboy';
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AdaptiveScaffold(
      header: AppHeader.greeting(
        greeting: _greeting(),
        name: nome,
        avatarInitials: initials,
        notificacoes: context.watch<NotificacaoProvider>().naoLidas,
        onNotificacoes: () =>
            Navigator.pushNamed(context, AppRoutes.notificacoes),
      ),
      bottomNav: AppBottomNav(
        userType: UserType.motoboy,
        currentIndex: 0,
        onTap: _onNav,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          _buildScoreRow(auth),
          const SizedBox(height: 12),
          _buildStats(),
          const SizedBox(height: 16),
          SectionTitle(title: 'Ganhos dos últimos dias'),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            // A série vem dos turnos já carregados, não do dashboard: o
            // endpoint não devolve `ganhosDiarios`, então o gráfico ficava
            // permanentemente zerado.
            child: Consumer<TurnoProvider>(
              builder: (context, provider, _) {
                final serie = serieUltimos7Dias(provider.meusTurnos, hoje: widget.agora);
                return MiniBarChart(
                  values: [for (final p in serie) p.valor],
                  labels: [for (final p in serie) p.label],
                );
              },
            ),
          ),
          SectionTitle(
            title: 'Turnos aceitos',
            action: 'Ver todos',
            onAction: () => Navigator.pushNamed(
                context, AppRoutes.turnosDisponiveis),
          ),
          _buildTurnosAceitosSection(),
        ],
      ),
      desktopTitle: 'Início',
      desktopSubtitle: '${_greeting()} $nome · ${_dataExtenso()}',
      desktopSelectedRoute: AppRoutes.dashboardMotoboy,
      desktopPrimaryAction: TopbarSecondaryButton(
        label: 'Buscar turnos',
        icon: Icons.search,
        onTap: () =>
            Navigator.pushNamed(context, AppRoutes.turnosDisponiveis),
      ),
      desktopBody: _buildDesktop(auth),
    );
  }

  String _dataExtenso() {
    final texto =
        DateFormat("EEEE, d 'de' MMMM", 'pt_BR')
            .format(widget.agora ?? clock.now());
    return texto[0].toUpperCase() + texto.substring(1);
  }

  // ── Métricas ──────────────────────────────────────────────────────────────

  double _score(AuthService auth) =>
      (_dashData?['score'] as num?)?.toDouble() ??
      auth.usuario?.score ??
      5.0;

  double get _saldo => (_dashData?['saldoAtual'] as num?)?.toDouble() ?? 0;

  double get _ganhosMensais =>
      (_dashData?['ganhosMensais'] as num?)?.toDouble() ?? 0;

  int get _turnosMes =>
      (_dashData?['turnosFinalizadosMes'] as num?)?.toInt() ?? 0;

  // ── Desktop ───────────────────────────────────────────────────────────────

  Widget _buildDesktop(AuthService auth) {
    final score = _score(auth);
    final mesAtual = DateFormat('MMMM', 'pt_BR').format(clock.now());

    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        final aceitos = provider.meusTurnos
            .where((t) =>
                t.status == StatusTurno.aceito ||
                t.status == StatusTurno.emAndamento)
            .toList()
          ..sort((a, b) => a.dataInicio.compareTo(b.dataInicio));

        return ContentGrid(
          children: [
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                minHeight: _alturaKpi,
                icon: Icons.military_tech_outlined,
                iconColor: AppColors.amber,
                label: 'Score de reputação',
                value: score.toStringAsFixed(2),
                sub: _scoreLabel(score),
                subColor: _scoreColor(score),
              ),
            ),
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                minHeight: _alturaKpi,
                icon: Icons.payments_outlined,
                label: 'Ganhos mês',
                value: 'R\$ ${_ganhosMensais.toStringAsFixed(0)}',
                sub: 'acumulado na carteira',
                subColor: AppColors.muted,
              ),
            ),
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                minHeight: _alturaKpi,
                icon: Icons.check_circle_outline,
                label: 'Turnos concluídos',
                value: '$_turnosMes',
                sub: 'em $mesAtual',
                subColor: AppColors.muted,
              ),
            ),
            GridCol(
              span: 3,
              child: WalletKpiCard(
                minHeight: _alturaKpi,
                label: 'Saldo',
                value: 'R\$ ${_saldo.toStringAsFixed(0)}',
                actionLabel: 'Sacar via Pix',
                onAction: () =>
                    Navigator.pushNamed(context, AppRoutes.sacarPix),
              ),
            ),
            GridCol(
              span: 8,
              child: WeeklyBarChartCard(
                title: 'Ganhos dos últimos dias',
                subtitle: 'Últimos 7 dias · turnos finalizados',
                carregando: provider.carregando,
                pontos: serieUltimos7Dias(provider.meusTurnos, hoje: widget.agora),
                mensagemVazio:
                    'Nenhum turno finalizado nos últimos 7 dias.',
              ),
            ),
            GridCol(
              span: 4,
              child: PanelCard(
                title: 'Turnos aceitos',
                actionLabel: 'Ver todos',
                onAction: () => Navigator.pushNamed(
                    context, AppRoutes.turnosDisponiveis),
                child: _buildAceitosDesktop(provider, aceitos),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAceitosDesktop(TurnoProvider provider, List<Turno> aceitos) {
    if (provider.carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.teal),
        ),
      );
    }
    if (aceitos.isEmpty) {
      return const InlineEmpty(
        icon: Icons.two_wheeler_outlined,
        titulo: 'Nenhum turno aceito',
        subtitulo: 'Explore os turnos disponíveis e comece a faturar.',
      );
    }
    return Column(
      children: [
        for (final t in aceitos.take(4)) ...[
          ShiftRow(
            horario: t.horarioFormatado,
            valor: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
            meta: '${t.titulo} · ${t.regiao}',
            icon: t.status == StatusTurno.emAndamento
                ? Icons.schedule_outlined
                : Icons.two_wheeler_outlined,
            amberIcon: t.status == StatusTurno.emAndamento,
            pillLabel: t.status.label,
            pillVariant: t.status == StatusTurno.emAndamento
                ? PillVariant.amber
                : PillVariant.teal,
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.detalheTurno,
              arguments: t,
            ),
          ),
          if (t != aceitos.take(4).last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Mobile ────────────────────────────────────────────────────────────────

  Widget _buildScoreRow(AuthService auth) {
    final score = _score(auth);
    final scoreC = _scoreColor(score);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: StatCard(
            label: 'Score de reputação',
            value: score.toStringAsFixed(2),
            sub: _scoreLabel(score),
            subColor: scoreC,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.carteira),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                gradient: AppColors.walletGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SALDO',
                      style: tsJakarta(8.5, FontWeight.w700,
                          color: const Color(0xFFBFE5E3))),
                  const SizedBox(height: 3),
                  Text(
                    'R\$ ${_saldo.toStringAsFixed(0)}',
                    style: tsBricolage(16, FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0x29FFFFFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                            size: 12),
                        const SizedBox(width: 4),
                        Text('Carteira',
                            style: tsJakarta(10, FontWeight.w700,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Ganhos mês',
            value: 'R\$ ${_ganhosMensais.toStringAsFixed(0)}',
            sub: '+ este mês',
            subColor: AppColors.good,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Turnos concluídos',
            value: '$_turnosMes',
          ),
        ),
      ],
    );
  }

  Widget _buildTurnosAceitosSection() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        if (provider.carregando) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.teal),
            ),
          );
        }
        final aceitos = provider.meusTurnos
            .where((t) =>
                t.status == StatusTurno.aceito ||
                t.status == StatusTurno.emAndamento)
            .toList();

        if (aceitos.isEmpty) {
          return const EmptyState(
            icon: Icons.two_wheeler_outlined,
            titulo: 'Nenhum turno aceito',
            subtitulo: 'Explore os turnos disponíveis e comece a faturar.',
          );
        }
        return Column(
          children: aceitos
              .map((t) => ShiftCard(
                    horario: t.horarioFormatado,
                    name: t.titulo,
                    meta: [t.regiao],
                    value: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                    iconData: Icons.two_wheeler_rounded,
                    pillLabel: t.status.label,
                    pillVariant: t.status == StatusTurno.emAndamento
                        ? PillVariant.amber
                        : PillVariant.teal,
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.detalheTurno,
                      arguments: t,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  String _scoreLabel(double score) {
    if (score >= 4.5) return 'Excelente';
    if (score >= 4.0) return 'Muito bom';
    if (score >= 3.0) return 'Bom';
    if (score >= 2.0) return 'Regular';
    return 'Precisa melhorar';
  }
}
