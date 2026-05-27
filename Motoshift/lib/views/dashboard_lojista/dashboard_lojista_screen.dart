import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Lojista';
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AppScaffold(
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _buildStats(),
          const SizedBox(height: 10),
          _buildPublicarBtn(),
          SectionTitle(
            title: 'Próximos turnos',
            action: 'Ver agenda',
            onAction: () => Navigator.pushNamed(context, AppRoutes.agenda),
          ),
          _buildTurnosSection(),
        ],
      ),
    );
  }

  Widget _buildStats() {
    if (_loadingDash) {
      return const SizedBox(
        height: 68,
        child: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.teal),
        ),
      );
    }
    final turnosAtivos =
        (_dashData?['turnosAtivos'] as num?)?.toInt() ?? 0;
    final totalGasto =
        (_dashData?['totalGasto'] as num?)?.toDouble() ?? 0.0;
    final avaliacaoMedia =
        (_dashData?['avaliacaoMedia'] as num?)?.toDouble() ?? 0.0;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Turnos ativos',
            value: '$turnosAtivos',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Gasto mês',
            value: 'R\$ ${totalGasto.toStringAsFixed(0)}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Avaliação',
            value: avaliacaoMedia > 0
                ? avaliacaoMedia.toStringAsFixed(1)
                : 'N/D',
            sub: avaliacaoMedia > 0 ? '★ média geral' : null,
            subColor: AppColors.amber,
          ),
        ),
      ],
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
              color: AppColors.amber.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded,
                color: Color(0xFF9A6206), size: 18),
            const SizedBox(width: 7),
            Text(
              'Publicar novo turno',
              style: tsJakarta(13, FontWeight.w700,
                  color: const Color(0xFF9A6206)),
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
                  strokeWidth: 2, color: AppColors.teal),
            ),
          );
        }
        if (provider.turnosLojista.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Center(
              child: Text(
                'Nenhum turno cadastrado ainda.\nPublique o primeiro!',
                textAlign: TextAlign.center,
                style: tsJakarta(13, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ),
          );
        }
        return Column(
          children: provider.turnosLojista
              .take(5)
              .map((t) => ShiftCard(
                    name: t.titulo,
                    meta: [
                      t.horarioFormatado,
                      t.regiao,
                      '${t.raioEntregaKm.toStringAsFixed(0)} km'
                    ],
                    value:
                        'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                    iconData: Icons.store_outlined,
                    pillLabel: t.status.label,
                    pillVariant: _pillFor(t.status),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.turnoLojista,
                      arguments: t,
                    ),
                  ))
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
