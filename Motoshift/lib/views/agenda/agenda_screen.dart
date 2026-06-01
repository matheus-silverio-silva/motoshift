import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/calendar_month.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  bool _carregando = false;

  DateTime _mesAtual = DateTime.now();
  Map<String, List<Map<String, dynamic>>> _turnosPorDia = {};
  int? _diaSelecionado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _carregarMensal());
  }

  Future<void> _carregarMensal() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    setState(() => _carregando = true);
    try {
      final data = await api.buscarAgendaMensal(
          id, _mesAtual.month, _mesAtual.year);
      final dias =
          (data['dias'] as List<dynamic>).cast<Map<String, dynamic>>();

      final Map<String, List<Map<String, dynamic>>> porDia = {};
      for (final dia in dias) {
        final dataStr = dia['data'] as String;
        final turnos = (dia['turnos'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        porDia[dataStr] = turnos;
      }
      if (mounted) setState(() => _turnosPorDia = porDia);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Set<int> get _marcados {
    return _turnosPorDia.entries
        .where((e) {
          final parts = e.key.split('-');
          if (parts.length < 2) return false;
          return int.tryParse(parts[1]) == _mesAtual.month;
        })
        .map((e) => int.parse(e.key.split('-')[2]))
        .toSet();
  }

  List<Map<String, dynamic>> get _turnosDiaSelecionado {
    if (_diaSelecionado == null) return [];
    final key =
        '${_mesAtual.year}-${_mesAtual.month.toString().padLeft(2, '0')}-${_diaSelecionado.toString().padLeft(2, '0')}';
    return _turnosPorDia[key] ?? [];
  }

  void _onNav(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacementNamed(context, AppRoutes.dashboardLojista);
      case 1:
        break;
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.turnosLojista);
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia,';
    if (h < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Usuário';
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
        currentIndex: 1,
        onTap: _onNav,
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.teal),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                CalendarMonth(
                  year: _mesAtual.year,
                  month: _mesAtual.month,
                  markedDays: _marcados,
                  selectedDay: _diaSelecionado,
                  today: DateTime.now().month == _mesAtual.month &&
                          DateTime.now().year == _mesAtual.year
                      ? DateTime.now().day
                      : null,
                  onDayTap: (d) => setState(() {
                    _diaSelecionado =
                        _diaSelecionado == d ? null : d;
                  }),
                ),
                // Month nav overlay on CalendarMonth header is handled
                // internally; provide prev/next via separate buttons below
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ArrowBtn(
                      onTap: () {
                        setState(() {
                          _mesAtual = DateTime(
                              _mesAtual.year, _mesAtual.month - 1);
                          _diaSelecionado = null;
                        });
                        _carregarMensal();
                      },
                      icon: Icons.chevron_left_rounded,
                      label: 'Mês anterior',
                    ),
                    const Spacer(),
                    _ArrowBtn(
                      onTap: () {
                        setState(() {
                          _mesAtual = DateTime(
                              _mesAtual.year, _mesAtual.month + 1);
                          _diaSelecionado = null;
                        });
                        _carregarMensal();
                      },
                      icon: Icons.chevron_right_rounded,
                      label: 'Próximo mês',
                      iconAtEnd: true,
                    ),
                  ],
                ),
                if (_diaSelecionado != null) ...[
                  const SizedBox(height: 14),
                  _buildDayDetail(),
                ],
              ],
            ),
    );
  }

  Widget _buildDayDetail() {
    final turnos = _turnosDiaSelecionado;
    final dayLabel =
        '$_diaSelecionado de ${_nomeMes(_mesAtual.month)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(dayLabel,
                style: tsBricolage(13, FontWeight.w800,
                    color: AppColors.ink)),
            const Spacer(),
            Text('${turnos.length} turno(s)',
                style: tsJakarta(10, FontWeight.w600,
                    color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 8),
        if (turnos.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Center(
              child: Text('Nenhum turno neste dia.',
                  style: tsJakarta(12.5, FontWeight.w400,
                      color: AppColors.muted)),
            ),
          )
        else
          ...turnos.map(_buildTurnoCard),
      ],
    );
  }

  Widget _buildTurnoCard(Map<String, dynamic> turno) {
    final status = turno['status'] as String? ?? '';
    final cor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: cor, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${turno['horarioInicio']} – ${turno['horarioFim']}',
                  style: tsJakarta(12.5, FontWeight.w700,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  turno['titulo'] as String? ?? '',
                  style: tsJakarta(10.5, FontWeight.w400,
                      color: AppColors.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(status),
                  style: tsJakarta(9.5, FontWeight.w700, color: cor),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'R\$ ${(turno['valorEstimado'] as num).toStringAsFixed(0)}',
                style: tsBricolage(12, FontWeight.w800,
                    color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status.toLowerCase()) {
        'aberto' => const Color(0xFF3B82F6),
        'aceito' => AppColors.amber,
        'emandamento' || 'em_andamento' => AppColors.teal,
        'finalizado' => AppColors.good,
        'cancelado' => AppColors.error,
        _ => AppColors.teal,
      };

  String _statusLabel(String status) => switch (status.toLowerCase()) {
        'aberto' => 'Aberto',
        'aceito' => 'Aceito',
        'emandamento' || 'em_andamento' => 'Em andamento',
        'finalizado' => 'Finalizado',
        'cancelado' => 'Cancelado',
        _ => status,
      };

  String _nomeMes(int mes) {
    const meses = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    return meses[mes - 1];
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({
    required this.onTap,
    required this.icon,
    required this.label,
    this.iconAtEnd = false,
  });
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool iconAtEnd;

  @override
  Widget build(BuildContext context) {
    final iconW = Icon(icon, size: 15, color: AppColors.teal);
    final textW = Text(label,
        style: tsJakarta(11, FontWeight.w600, color: AppColors.teal));
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: iconAtEnd
            ? [textW, const SizedBox(width: 3), iconW]
            : [iconW, const SizedBox(width: 3), textW],
      ),
    );
  }
}
