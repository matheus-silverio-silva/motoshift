import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
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
import '../../widgets/desktop/weekly_bar_chart_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_title.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_pill.dart';

class DashboardLojistScreen extends StatefulWidget {
  const DashboardLojistScreen({super.key});

  @override
  State<DashboardLojistScreen> createState() => _DashboardLojistScreenState();
}

class _DashboardLojistScreenState extends State<DashboardLojistScreen> {
  Map<String, dynamic>? _dashData;
  bool _loadingDash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final turnoProvider = context.read<TurnoProvider>();
    final id = auth.usuario?.id;
    if (id == null) return;

    setState(() => _loadingDash = true);
    try {
      final data = await api.dashboardLojista(id);
      if (mounted) setState(() => _dashData = data);
    } catch (_) {}
    if (mounted) setState(() => _loadingDash = false);

    turnoProvider.carregarTurnosLojista(id);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia,';
    if (h < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  void _onNav(int i) {
    switch (i) {
      case 0:
        break;
      case 1:
        Navigator.pushReplacementNamed(context, AppRoutes.agenda);
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.turnosLojista);
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
  }

  // ── Métricas ──────────────────────────────────────────────────────────────

  int get _turnosAtivos => (_dashData?['turnosAtivos'] as num?)?.toInt() ?? 0;

  /// Soma dos turnos finalizados, sem recorte de data — é o que
  /// `DashboardController.totalGasto` devolve. O protótipo pede "gasto no mês";
  /// enquanto o backend não expuser esse campo, o rótulo acompanha o dado.
  double get _totalGasto => (_dashData?['totalGasto'] as num?)?.toDouble() ?? 0;

  int get _turnosFinalizados =>
      (_dashData?['turnosFinalizados'] as num?)?.toInt() ?? 0;

  int get _turnosMes => (_dashData?['turnosMes'] as num?)?.toInt() ?? 0;

  /// Nota que este lojista recebeu (não a reputação dos entregadores dele).
  double get _avaliacaoMedia =>
      (_dashData?['avaliacaoMedia'] as num?)?.toDouble() ?? 0;

  int _comecamHoje(List<Turno> turnos) {
    final hoje = DateTime.now();
    return turnos
        .where(
          (t) =>
              t.status.ativo &&
              t.dataInicio.year == hoje.year &&
              t.dataInicio.month == hoje.month &&
              t.dataInicio.day == hoje.day,
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Lojista';
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AdaptiveScaffold(
      header: AppHeader.greeting(
        greeting: _greeting(),
        name: nome,
        avatarInitials: initials,
      ),
      bottomNav: AppBottomNav(
        userType: UserType.lojista,
        currentIndex: 0,
        onTap: _onNav,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          _buildStats(),
          const SizedBox(height: 14),
          _buildPublicarBtn(),
          SectionTitle(
            title: 'Próximos turnos',
            action: 'Ver agenda',
            onAction: () => Navigator.pushNamed(context, AppRoutes.agenda),
          ),
          _buildTurnosSection(),
        ],
      ),
      desktopTitle: 'Início',
      desktopSubtitle: '${_greeting()} $nome · ${_dataExtenso()}',
      desktopSelectedRoute: AppRoutes.dashboardLojista,
      desktopPrimaryAction: TopbarPrimaryButton(
        label: 'Publicar turno',
        icon: Icons.add,
        onTap: () => Navigator.pushNamed(context, AppRoutes.publicarTurno),
      ),
      desktopBody: _buildDesktop(),
    );
  }

  String _dataExtenso() {
    final texto = DateFormat(
      "EEEE, d 'de' MMMM",
      'pt_BR',
    ).format(DateTime.now());
    return texto[0].toUpperCase() + texto.substring(1);
  }

  // ── Desktop ───────────────────────────────────────────────────────────────

  Widget _buildDesktop() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        final proximos = provider.turnosLojista.proximos();
        final hoje = _comecamHoje(provider.turnosLojista);

        return ContentGrid(
          children: [
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                icon: Icons.local_shipping_outlined,
                label: 'Turnos ativos',
                value: '$_turnosAtivos',
                // Sempre com subtítulo: no grid do protótipo os quatro KPIs
                // têm a mesma altura, e é a linha de baixo que a define.
                sub: hoje > 0
                    ? '$hoje ${hoje == 1 ? 'começa' : 'começam'} hoje'
                    : 'nenhum começa hoje',
                subColor: hoje > 0 ? AppColors.good : AppColors.muted,
              ),
            ),
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                icon: Icons.payments_outlined,
                label: 'Gasto total',
                value: 'R\$ ${_totalGasto.toStringAsFixed(0)}',
                sub:
                    '$_turnosFinalizados ${_turnosFinalizados == 1 ? 'turno finalizado' : 'turnos finalizados'}',
                subColor: AppColors.muted,
              ),
            ),
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                icon: Icons.event_note_outlined,
                label: 'Turnos no mês',
                value: '$_turnosMes',
                sub: 'publicados',
                subColor: AppColors.muted,
              ),
            ),
            GridCol(
              span: 3,
              child: StatCard(
                size: StatCardSize.large,
                icon: Icons.star_outline_rounded,
                iconColor: AppColors.amber,
                label: 'Avaliação',
                value: _avaliacaoMedia > 0
                    ? _avaliacaoMedia.toStringAsFixed(1)
                    : 'N/D',
                sub: _avaliacaoMedia > 0 ? '★ recebida' : 'sem notas',
                subColor: AppColors.amber,
              ),
            ),
            GridCol(
              span: 8,
              child: WeeklyBarChartCard(
                title: 'Gasto com turnos',
                subtitle: 'Últimos 7 dias · turnos finalizados',
                carregando: provider.carregando,
                pontos: serieUltimos7Dias(provider.turnosLojista),
                mensagemVazio: 'Nenhum turno finalizado nos últimos 7 dias.',
              ),
            ),
            GridCol(
              span: 4,
              child: PanelCard(
                title: 'Próximos turnos',
                actionLabel: 'Ver agenda',
                onAction: () => Navigator.pushNamed(context, AppRoutes.agenda),
                child: _buildProximosDesktop(provider, proximos),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProximosDesktop(TurnoProvider provider, List<Turno> proximos) {
    if (provider.carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.teal,
          ),
        ),
      );
    }
    if (proximos.isEmpty) {
      return InlineEmpty(
        icon: Icons.event_available_outlined,
        titulo: provider.turnosLojista.isEmpty
            ? 'Nenhum turno cadastrado'
            : 'Nenhum turno agendado',
        subtitulo: provider.turnosLojista.isEmpty
            ? 'Publique o primeiro e receba entregadores na sua região.'
            : 'Seus turnos anteriores estão no histórico.',
      );
    }
    return Column(
      children: [
        for (final t in proximos.take(4)) ...[
          ShiftRow(
            horario: t.horarioFormatado,
            valor: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
            meta: _metaDoTurno(t),
            icon: t.status == StatusTurno.emAndamento
                ? Icons.schedule_outlined
                : Icons.storefront_outlined,
            amberIcon: t.status == StatusTurno.emAndamento,
            pillLabel: t.status.label,
            pillVariant: _pillFor(t.status),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.turnoLojista,
              arguments: t,
            ),
          ),
          if (t != proximos.take(4).last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _metaDoTurno(Turno t) {
    final partes = <String>[t.titulo, t.regiao];
    if (t.multiVaga && t.vagasRestantes > 0) {
      partes.add(
        '${t.vagasRestantes} ${t.vagasRestantes == 1 ? 'vaga' : 'vagas'}',
      );
    }
    return partes.join(' · ');
  }

  // ── Mobile ────────────────────────────────────────────────────────────────

  Widget _buildStats() {
    if (_loadingDash) {
      return const SizedBox(
        height: 68,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.teal,
          ),
        ),
      );
    }

    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        final hoje = _comecamHoje(provider.turnosLojista);
        // IntrinsicHeight + stretch: no artboard os três cards têm a mesma
        // altura, e o subtítulo do primeiro some quando não há turno hoje.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatCard(
                  label: 'Turnos ativos',
                  value: '$_turnosAtivos',
                  sub: hoje > 0 ? '$hoje hoje' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Gasto total',
                  value: 'R\$ ${_totalGasto.toStringAsFixed(0)}',
                  sub: '$_turnosFinalizados turnos',
                  subColor: AppColors.muted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Avaliação',
                  value: _avaliacaoMedia > 0
                      ? _avaliacaoMedia.toStringAsFixed(1)
                      : 'N/D',
                  sub: _avaliacaoMedia > 0 ? '★ recebida' : 'sem notas',
                  subColor: AppColors.amber,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPublicarBtn() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.publicarTurno),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.amberSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.amber.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: Color(0xFF9A6206), size: 18),
            const SizedBox(width: 7),
            Text(
              'Publicar novo turno',
              style: tsJakarta(
                13,
                FontWeight.w700,
                color: const Color(0xFF9A6206),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnosSection() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        if (provider.carregando) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.teal,
              ),
            ),
          );
        }
        // A seção se chama "Próximos turnos": mostra apenas turnos ativos que
        // ainda não terminaram, do mais próximo ao mais distante. Antes usava
        // a lista crua do provider, que vem do backend sem filtro nem ordem —
        // por isso cancelados e finalizados apareciam aqui.
        final proximos = provider.turnosLojista.proximos();

        if (proximos.isEmpty) {
          return EmptyState(
            icon: Icons.event_available_outlined,
            titulo: provider.turnosLojista.isEmpty
                ? 'Nenhum turno cadastrado'
                : 'Nenhum turno agendado',
            subtitulo: provider.turnosLojista.isEmpty
                ? 'Publique o primeiro e receba entregadores na sua região.'
                : 'Seus turnos anteriores estão no histórico. Publique um novo para continuar.',
          );
        }
        return Column(
          children: proximos
              .take(5)
              .map(
                (t) => ShiftCard(
                  name: t.titulo,
                  meta: [
                    t.horarioFormatado,
                    t.regiao,
                    '${t.raioEntregaKm.toStringAsFixed(0)} km',
                  ],
                  value: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                  iconData: Icons.store_outlined,
                  pillLabel: t.status.label,
                  pillVariant: _pillFor(t.status),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.turnoLojista,
                    arguments: t,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  PillVariant _pillFor(StatusTurno s) => switch (s) {
    StatusTurno.aceito => PillVariant.teal,
    StatusTurno.emAndamento => PillVariant.amber,
    StatusTurno.finalizado => PillVariant.good,
    _ => PillVariant.ghost,
  };
}
