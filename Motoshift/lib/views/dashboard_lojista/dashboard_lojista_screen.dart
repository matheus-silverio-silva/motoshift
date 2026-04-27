import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_app_bar.dart';
import '../../widgets/kinetic_bottom_nav.dart';
import '../relatorio/relatorio_screen.dart';

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
          const SizedBox(height: 16),
          _buildRelatorioCard(),
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

  Widget _buildRelatorioCard() {
    final meses = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho',
                   'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
    final now = DateTime.now();
    final mesAtual = '${meses[now.month - 1]} ${now.year}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppColors.kineticGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('📊', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Análise do seu mês',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 11, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Gerado por IA · $mesAtual',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _abrirRelatorio,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.kineticGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Ver relatório',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirRelatorio() async {
    final turnosMes = (_dashData?['turnosMes'] as num?)?.toInt() ?? 0;

    if (turnosMes < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publique pelo menos 3 turnos para gerar sua análise.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text(
                  'Analisando seus dados...',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final data = await api.buscarRelatorioLojista(id);
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RelatorioScreen(
            periodo: data['periodo'] as String,
            perfil: data['perfil'] as String,
            relatorio: data['relatorio'] as String,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível gerar o relatório. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

    final turnosMes        = _dashData?['turnosMes'] ?? 0;
    final turnosAtivos     = _dashData?['turnosAtivos'] ?? 0;
    final turnosFinalizados = _dashData?['turnosFinalizados'] ?? 0;
    final totalGasto       = (_dashData?['totalGasto'] as num?)?.toDouble() ?? 0.0;
    final avaliacaoMedia   = (_dashData?['avaliacaoMedia'] as num?)?.toDouble() ?? 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _statCard('Publicados no Mês', '$turnosMes', AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('Ativos Agora', '$turnosAtivos', null)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statCard('Finalizados', '$turnosFinalizados', const Color(0xFF00875A))),
            const SizedBox(width: 12),
            Expanded(child: _statCard('Total Gasto', 'R\$ ${totalGasto.toStringAsFixed(0)}', null)),
          ],
        ),
        const SizedBox(height: 12),
        _avaliacaoCard(avaliacaoMedia),
      ],
    );
  }

  Widget _statCard(String label, String value, Color? valueColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
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
            value,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: valueColor ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avaliacaoCard(double media) {
    final estrelasCheias = media.floor();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AVALIAÇÃO MÉDIA DOS MOTOBOYS',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  media > 0 ? media.toStringAsFixed(1) : 'N/D',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (media > 0)
            Row(
              children: List.generate(5, (i) => Icon(
                i < estrelasCheias
                    ? Icons.star_rounded
                    : (i == estrelasCheias && media - estrelasCheias >= 0.5
                        ? Icons.star_half_rounded
                        : Icons.star_outline_rounded),
                color: AppColors.primary,
                size: 22,
              )),
            ),
        ],
      ),
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

