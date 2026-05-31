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
import '../../widgets/mini_bar_chart.dart';
import '../../widgets/section_title.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_pill.dart';


class DashboardMotoboyScreen extends StatefulWidget {
  const DashboardMotoboyScreen({super.key});

  @override
  State<DashboardMotoboyScreen> createState() =>
      _DashboardMotoboyScreenState();
}

class _DashboardMotoboyScreenState extends State<DashboardMotoboyScreen> {
  Map<String, dynamic>? _dashData;
  // TODO: integrar ganhosDiarios com backend
  List<double> _ganhosDiarios = List.filled(7, 0.0);

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

    try {
      final data = await api.dashboardMotoboy(id);
      if (mounted) {
        final raw = data['ganhosDiarios'];
        setState(() {
          _dashData = data;
          if (raw is List && raw.length == 7) {
            _ganhosDiarios =
                raw.map((e) => (e as num).toDouble()).toList();
          }
        });
      }
    } catch (_) {}
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

    return AppScaffold(
      header: AppHeader.greeting(
        greeting: _greeting(),
        name: nome,
        avatarInitials: initials,
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
            child: MiniBarChart(
              values: _ganhosDiarios,
              labels: const [
                'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'
              ],
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
    );
  }

  Widget _buildScoreRow(AuthService auth) {
    final score = (_dashData?['score'] as num?)?.toDouble() ??
        auth.usuario?.score ??
        5.0;
    final saldo =
        (_dashData?['saldoAtual'] as num?)?.toDouble() ?? 0.0;
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
                    'R\$ ${saldo.toStringAsFixed(0)}',
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
    final ganhos =
        (_dashData?['ganhosMensais'] as num?)?.toDouble() ?? 0.0;
    final turnos =
        (_dashData?['turnosFinalizadosMes'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Ganhos mês',
            value: 'R\$ ${ganhos.toStringAsFixed(0)}',
            sub: '+ este mês',
            subColor: AppColors.good,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Turnos concluídos',
            value: '$turnos',
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
          return Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Center(
              child: Text(
                'Nenhum turno aceito no momento.\nExplorare os turnos disponíveis!',
                textAlign: TextAlign.center,
                style: tsJakarta(12.5, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ),
          );
        }
        return Column(
          children: aceitos
              .map((t) => ShiftCard(
                    name: t.titulo,
                    meta: [t.horarioFormatado, t.regiao],
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
