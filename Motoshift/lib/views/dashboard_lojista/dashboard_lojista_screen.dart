import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_app_bar.dart';
import '../../widgets/kinetic_bottom_nav.dart';

class DashboardLojistScreen extends StatefulWidget {
  const DashboardLojistScreen({super.key});

  @override
  State<DashboardLojistScreen> createState() => _DashboardLojistScreenState();
}

class _DashboardLojistScreenState extends State<DashboardLojistScreen> {
  NavItem _navItem = NavItem.dashboard;
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

  void _onNavChanged(NavItem item) {
    setState(() => _navItem = item);
    switch (item) {
      case NavItem.dashboard:
        break;
      case NavItem.turnos:
        Navigator.pushNamed(context, '/agendar-turno');
        break;
      case NavItem.carteira:
        Navigator.pushNamed(context, '/carteira');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Lojista';

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: KineticAppBar(
        avatarUrl: auth.usuario?.fotoPerfil,
        onNotificationTap: () {},
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 80, bottom: 120, left: 24, right: 24),
        children: [
          const SizedBox(height: 24),
          _buildHeroSection(nome),
          const SizedBox(height: 32),
          _buildStatsBento(),
          const SizedBox(height: 32),
          Row(
            children: [
              const Text(
                'Turnos Recentes',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _carregar,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text(
                  'Atualizar',
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
          const SizedBox(height: 16),
          _buildTurnosSection(),
        ],
      ),
      bottomNavigationBar: KineticBottomNav(
        currentItem: _navItem,
        onItemSelected: _onNavChanged,
      ),
    );
  }

  Widget _buildHeroSection(String nome) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: AppColors.kineticGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.kineticShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Olá, $nome!',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gerencie seus turnos e otimize a logística da sua loja.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.85),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/agendar-turno'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline, color: AppColors.primary, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Agendar Turno',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBento() {
    if (_loadingDash) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final turnosAtivos = _dashData?['turnosAtivos'] ?? 0;
    final turnosFinalizados = _dashData?['turnosFinalizados'] ?? 0;
    final totalGasto = (_dashData?['totalGasto'] as num?)?.toDouble() ?? 0.0;

    final stats = [
      _StatItem('Turnos Ativos', '$turnosAtivos', AppColors.primary),
      _StatItem('Finalizados', '$turnosFinalizados', const Color(0xFF00875A)),
      _StatItem('Total Gasto', 'R\$ ${totalGasto.toStringAsFixed(0)}', null),
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: s == stats.last ? 0 : 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.value,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: s.color ?? AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTurnosSection() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        if (provider.carregando) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }
        if (provider.erro != null) {
          return _erroCard(provider.erro!, onRetry: () {
            provider.limparErro();
            _carregar();
          });
        }
        if (provider.turnosLojista.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Nenhum turno cadastrado ainda. Agende o primeiro!',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return Column(
          children: provider.turnosLojista
              .take(10)
              .map((t) => _buildTurnoCard(t, provider))
              .toList(),
        );
      },
    );
  }

  Widget _buildTurnoCard(Turno turno, TurnoProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: turno.status == StatusTurno.finalizado
            ? AppColors.surfaceContainerLowest.withOpacity(0.7)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _iconBgFor(turno.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(turno.status), color: _iconColorFor(turno.status), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turno.titulo,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(turno.dataInicio)} · ${turno.horarioFormatado}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _statusBadge(turno.status),
              if (turno.status != StatusTurno.finalizado &&
                  turno.status != StatusTurno.cancelado) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final ok = await provider.cancelarTurno(turno.id!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Turno cancelado.' : (provider.erro ?? 'Erro')),
                        backgroundColor: ok ? Colors.orange : Colors.red,
                      ));
                    }
                  },
                  child: const Icon(Icons.cancel_outlined,
                      color: AppColors.onSurfaceVariant, size: 22),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _erroCard(String msg, {required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.onSurfaceVariant, size: 40),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Manrope', color: AppColors.onSurfaceVariant)),
          TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }

  Widget _statusBadge(StatusTurno status) {
    Color bg;
    Color fg;
    switch (status) {
      case StatusTurno.aceito:
        bg = AppColors.primaryFixed;
        fg = AppColors.onPrimaryFixed;
        break;
      case StatusTurno.aberto:
        bg = AppColors.secondaryContainer;
        fg = AppColors.onSecondaryContainer;
        break;
      default:
        bg = AppColors.surfaceContainerHighest;
        fg = AppColors.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: fg,
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const meses = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
    return '${d.day.toString().padLeft(2, '0')} ${meses[d.month - 1]}';
  }

  Color _iconBgFor(StatusTurno s) => switch (s) {
    StatusTurno.aceito => AppColors.primary.withOpacity(0.05),
    StatusTurno.aberto => AppColors.surfaceContainerHighest,
    _ => AppColors.surfaceContainerHigh,
  };

  IconData _iconFor(StatusTurno s) => switch (s) {
    StatusTurno.aceito => Icons.local_shipping_outlined,
    StatusTurno.aberto => Icons.inventory_2_outlined,
    StatusTurno.finalizado => Icons.check_circle_outline,
    _ => Icons.schedule_outlined,
  };

  Color _iconColorFor(StatusTurno s) => switch (s) {
    StatusTurno.aceito => AppColors.primary,
    _ => AppColors.onSurfaceVariant,
  };
}

class _StatItem {
  final String label;
  final String value;
  final Color? color;
  const _StatItem(this.label, this.value, this.color);
}
