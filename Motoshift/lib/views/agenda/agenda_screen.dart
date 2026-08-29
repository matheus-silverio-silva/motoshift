import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/calendar_month.dart';
import '../../widgets/desktop/app_topbar.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, this.agora});

  /// Fixa o "agora" da tela. Só os testes passam isto.
  ///
  /// Esta tela lê o relógio em cinco pontos — o anel do dia de hoje no
  /// calendário, o mês inicial, a semana do resumo e a saudação por faixa de
  /// hora. Com `DateTime.now()` espalhado, o golden dela passava só na máquina
  /// e no momento em que foi gravado: o baseline de 19/08 falhava em qualquer
  /// outro dia do mês, com o anel do "hoje" fora do lugar.
  final DateTime? agora;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  bool _carregando = false;

  /// Lido uma vez só: duas leituras do relógio no mesmo build podiam cair em
  /// lados opostos da virada do dia.
  late final DateTime _agora = widget.agora ?? clock.now();

  late DateTime _mesAtual = _agora;
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
      final data = await api.agenda.buscarAgendaMensal(
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
    final h = _agora.hour;
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
    final ehLojista = auth.usuario?.tipo == TipoUsuario.lojista;

    return AdaptiveScaffold(
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
      desktopTitle: 'Agenda',
      desktopSubtitle: _subtituloDesktop(),
      desktopSelectedRoute: AppRoutes.agenda,
      desktopPrimaryAction: ehLojista
          ? TopbarPrimaryButton(
              label: 'Publicar turno',
              icon: Icons.add,
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.publicarTurno),
            )
          : null,
      desktopBody: _buildDesktop(),
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
                  today: _agora.month == _mesAtual.month &&
                          _agora.year == _mesAtual.year
                      ? _agora.day
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

  // ── Desktop — calendário à esquerda, dia selecionado à direita ───────────

  String _subtituloDesktop() {
    if (_carregando) return 'Carregando agenda…';
    final n = _marcados.length;
    final mes = '${_nomeMesCompleto(_mesAtual.month)} de ${_mesAtual.year}';
    if (n == 0) return '$mes · nenhum dia com turno';
    return '$mes · $n ${n == 1 ? 'dia com turno' : 'dias com turno'}';
  }

  void _mudarMes(int delta) {
    setState(() {
      _mesAtual = DateTime(_mesAtual.year, _mesAtual.month + delta);
      _diaSelecionado = null;
    });
    _carregarMensal();
  }

  Widget _buildDesktop() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.teal),
      );
    }
    return ContentGrid(
      children: [
        GridCol(
          span: 7,
          child: CalendarMonth(
            year: _mesAtual.year,
            month: _mesAtual.month,
            markedDays: _marcados,
            selectedDay: _diaSelecionado,
            today: _agora.month == _mesAtual.month &&
                    _agora.year == _mesAtual.year
                ? _agora.day
                : null,
            onMonthChange: _mudarMes,
            onDayTap: (d) => setState(() {
              _diaSelecionado = _diaSelecionado == d ? null : d;
            }),
            footer: _buildLegenda(),
          ),
        ),
        GridCol(
          span: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDiaDesktop(),
              const SizedBox(height: 16),
              _buildResumoSemana(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegenda() {
    Widget item(Widget marca, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            marca,
            const SizedBox(width: 6),
            Text(texto,
                style:
                    tsJakarta(11.5, FontWeight.w400, color: AppColors.muted)),
          ],
        );

    return Row(
      children: [
        item(
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: AppColors.amber, shape: BoxShape.circle),
          ),
          'dia com turno',
        ),
        const SizedBox(width: 16),
        item(
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.teal, width: 1.5),
            ),
          ),
          'hoje',
        ),
        const SizedBox(width: 16),
        item(
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.teal,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          'selecionado',
        ),
      ],
    );
  }

  Widget _buildDiaDesktop() {
    if (_diaSelecionado == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.calendar_month_outlined,
                  size: 26, color: AppColors.tealDeep),
            ),
            const SizedBox(height: 14),
            Text('Selecione um dia',
                style:
                    tsBricolage(16, FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 5),
            Text(
              'Escolha uma data no calendário para ver os turnos daquele dia.',
              textAlign: TextAlign.center,
              style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    final turnos = _turnosDiaSelecionado;
    final total = turnos.fold<double>(
        0, (a, t) => a + ((t['valorEstimado'] as num?)?.toDouble() ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                '$_diaSelecionado de ${_nomeMesCompleto(_mesAtual.month)}',
                style:
                    tsBricolage(20, FontWeight.w800, color: AppColors.ink),
              ),
            ),
            Text(
              turnos.isEmpty
                  ? 'sem turnos'
                  : '${turnos.length} ${turnos.length == 1 ? 'turno' : 'turnos'} · R\$ ${total.toStringAsFixed(0)}',
              style: tsJakarta(12, FontWeight.w600, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (turnos.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
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
          for (final t in turnos) ...[
            _buildTurnoCard(t),
          ],
      ],
    );
  }

  /// Resumo da semana do dia selecionado (ou da semana corrente), derivado
  /// dos turnos do mês que a tela já carregou.
  Widget _buildResumoSemana() {
    final referencia = _diaSelecionado != null
        ? DateTime(_mesAtual.year, _mesAtual.month, _diaSelecionado!)
        : _agora;
    final inicioSemana =
        referencia.subtract(Duration(days: referencia.weekday % 7));
    final fimSemana = inicioSemana.add(const Duration(days: 6));

    var publicados = 0;
    var preenchidos = 0;
    var custo = 0.0;
    for (final entry in _turnosPorDia.entries) {
      final dia = DateTime.tryParse(entry.key);
      if (dia == null) continue;
      if (dia.isBefore(inicioSemana) || dia.isAfter(fimSemana)) continue;
      for (final t in entry.value) {
        publicados++;
        final status = (t['status'] as String? ?? '').toLowerCase();
        if (status != 'aberto') preenchidos++;
        custo += (t['valorEstimado'] as num?)?.toDouble() ?? 0;
      }
    }

    Widget linha(String rotulo, String valor) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(rotulo,
                    style: tsJakarta(12.5, FontWeight.w400,
                        color: AppColors.muted)),
              ),
              Text(valor,
                  style: tsJakarta(12.5, FontWeight.w700,
                      color: AppColors.text)),
            ],
          ),
        );

    return PanelCard(
      title: 'Resumo da semana',
      padding: const EdgeInsets.all(18),
      gap: 0,
      child: Column(
        children: [
          linha('Turnos publicados', '$publicados'),
          linha('Preenchidos', '$preenchidos'),
          linha('Custo previsto', 'R\$ ${custo.toStringAsFixed(0)}'),
        ],
      ),
    );
  }

  String _nomeMesCompleto(int mes) {
    const meses = [
      'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
    ];
    return meses[mes - 1];
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
