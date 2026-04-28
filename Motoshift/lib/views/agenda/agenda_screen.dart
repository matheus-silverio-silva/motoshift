import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_app_bar.dart';
import '../../widgets/kinetic_bottom_nav.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _carregando = false;
  String? _erro;

  // Mensal
  DateTime _mesAtual = DateTime.now();
  Map<String, List<Map<String, dynamic>>> _turnosPorDia = {};

  // Semanal
  DateTime _semanaBase = DateTime.now();
  List<Map<String, dynamic>> _diasSemana = [];
  int _diaSelecionado = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarMensal();
      _carregarSemanal();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    if (_tabController.index == 0) _carregarMensal();
    if (_tabController.index == 1) _carregarSemanal();
  }

  Future<void> _carregarMensal() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final data = await api.buscarAgendaMensal(
          id, _mesAtual.month, _mesAtual.year);
      final dias = (data['dias'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final Map<String, List<Map<String, dynamic>>> porDia = {};
      for (final dia in dias) {
        final dataStr = dia['data'] as String;
        final turnos = (dia['turnos'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        porDia[dataStr] = turnos;
      }
      if (mounted) setState(() => _turnosPorDia = porDia);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar agenda.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _carregarSemanal() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    final dataStr =
        '${_semanaBase.year}-${_semanaBase.month.toString().padLeft(2, '0')}-${_semanaBase.day.toString().padLeft(2, '0')}';

    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final data = await api.buscarAgendaSemanal(id, dataStr);
      final dias = (data['dias'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _diasSemana = dias;
          _diaSelecionado = 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar agenda.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: KineticAppBar(
        avatarUrl: auth.usuario?.fotoPerfil,
        onNotificationTap: () {},
      ),
      body: Column(
        children: [
          const SizedBox(height: 96),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Minha Agenda',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.onSurfaceVariant,
                tabs: const [
                  Tab(text: 'Mensal'),
                  Tab(text: 'Semanal'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMensalTab(),
                _buildSemanalTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: KineticBottomNav(
        currentItem: NavItem.agenda,
        onItemSelected: (item) {
          switch (item) {
            case NavItem.dashboard:
              Navigator.pop(context);
            case NavItem.turnos:
              Navigator.pushReplacementNamed(context, '/meus-turnos');
            case NavItem.carteira:
              Navigator.pushReplacementNamed(context, '/carteira');
            case NavItem.agenda:
              break;
          }
        },
      ),
    );
  }

  // ─── TAB MENSAL ──────────────────────────────────────────

  Widget _buildMensalTab() {
    return Column(
      children: [
        // Navegação mês
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(
                      () => _mesAtual = DateTime(_mesAtual.year, _mesAtual.month - 1));
                  _carregarMensal();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: AppColors.onSurface, size: 20),
                ),
              ),
              Expanded(
                child: Text(
                  '${_nomeMes(_mesAtual.month)} ${_mesAtual.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(
                      () => _mesAtual = DateTime(_mesAtual.year, _mesAtual.month + 1));
                  _carregarMensal();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.onSurface, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Cabeçalho dias da semana
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']
                .map((d) => Expanded(
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Grade do calendário
        if (_carregando)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (_erro != null)
          Expanded(
            child: Center(
              child: Text(_erro!,
                  style: const TextStyle(
                      fontFamily: 'Manrope',
                      color: AppColors.onSurfaceVariant)),
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildCalendarioGrid(),
            ),
          ),
      ],
    );
  }

  Widget _buildCalendarioGrid() {
    final primeiroDia = DateTime(_mesAtual.year, _mesAtual.month, 1);
    final ultimoDia = DateTime(_mesAtual.year, _mesAtual.month + 1, 0);
    final offsetInicio = primeiroDia.weekday % 7; // 0=Dom

    final List<Widget> cells = [];

    // Células vazias antes do primeiro dia
    for (int i = 0; i < offsetInicio; i++) {
      cells.add(const SizedBox());
    }

    // Dias do mês
    for (int dia = 1; dia <= ultimoDia.day; dia++) {
      final dateStr =
          '${_mesAtual.year}-${_mesAtual.month.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
      final turnos = _turnosPorDia[dateStr] ?? [];
      final isHoje = DateTime.now().day == dia &&
          DateTime.now().month == _mesAtual.month &&
          DateTime.now().year == _mesAtual.year;

      cells.add(
        GestureDetector(
          onTap: turnos.isNotEmpty
              ? () => _mostrarDetalhesDia(dateStr, turnos)
              : null,
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isHoje
                  ? AppColors.primary.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isHoje
                  ? Border.all(color: AppColors.primary.withOpacity(0.4))
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$dia',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight:
                        isHoje ? FontWeight.w800 : FontWeight.w500,
                    color: isHoje
                        ? AppColors.primary
                        : AppColors.onSurface,
                  ),
                ),
                if (turnos.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    children: turnos
                        .take(3)
                        .map((t) => Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _statusColor(t['status'] as String),
                                shape: BoxShape.circle,
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: cells,
    );
  }

  // ─── TAB SEMANAL ─────────────────────────────────────────

  Widget _buildSemanalTab() {
    return Column(
      children: [
        // Navegação semana
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() =>
                      _semanaBase = _semanaBase.subtract(const Duration(days: 7)));
                  _carregarSemanal();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: AppColors.onSurface, size: 20),
                ),
              ),
              Expanded(
                child: Text(
                  _labelSemana(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() =>
                      _semanaBase = _semanaBase.add(const Duration(days: 7)));
                  _carregarSemanal();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.onSurface, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Chips dos 7 dias
        if (_diasSemana.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _diasSemana.length,
              itemBuilder: (context, i) {
                final dia = _diasSemana[i];
                final dataStr = dia['data'] as String;
                final turnos = (dia['turnos'] as List<dynamic>)
                    .cast<Map<String, dynamic>>();
                final date = DateTime.parse(dataStr);
                final isSelected = i == _diaSelecionado;
                final isHoje = _isHoje(date);

                return GestureDetector(
                  onTap: () => setState(() => _diaSelecionado = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: isHoje && !isSelected
                          ? Border.all(
                              color: AppColors.primary.withOpacity(0.5))
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _diaSemanaAbrev(date.weekday),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white70
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? Colors.white
                                : AppColors.onSurface,
                          ),
                        ),
                        if (turnos.isNotEmpty)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white54
                                  : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
        // Turnos do dia selecionado
        if (_carregando)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else
          Expanded(
            child: _buildTurnosDiaSelecionado(),
          ),
      ],
    );
  }

  Widget _buildTurnosDiaSelecionado() {
    if (_diasSemana.isEmpty) {
      return const Center(
        child: Text('Nenhum dado disponível.',
            style: TextStyle(
                fontFamily: 'Manrope', color: AppColors.onSurfaceVariant)),
      );
    }

    final dia = _diasSemana[_diaSelecionado];
    final turnos = (dia['turnos'] as List<dynamic>).cast<Map<String, dynamic>>();

    if (turnos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_rounded,
                size: 48,
                color: AppColors.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'Nenhum turno neste dia',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: turnos.length,
      itemBuilder: (context, i) => _buildTurnoCard(turnos[i]),
    );
  }

  Widget _buildTurnoCard(Map<String, dynamic> turno) {
    final status = turno['status'] as String;
    final cor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
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
                  '${turno['horarioInicio']} - ${turno['horarioFim']}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  turno['titulo'] as String? ?? '',
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: cor,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'R\$ ${(turno['valorEstimado'] as num).toStringAsFixed(2).replaceAll('.', ',')}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── BottomSheet de detalhes do dia ──────────────────────

  void _mostrarDetalhesDia(
      String dataStr, List<Map<String, dynamic>> turnos) {
    final date = DateTime.parse(dataStr);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${date.day} de ${_nomeMes(date.month)}',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${turnos.length} turno(s)',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: turnos.map(_buildTurnoCard).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────

  Color _statusColor(String status) {
    return switch (status.toLowerCase()) {
      'aberto' => const Color(0xFF3B82F6),
      'aceito' => const Color(0xFFF59E0B),
      'emandamento' || 'em_andamento' => AppColors.primary,
      'finalizado' => const Color(0xFF6B7280),
      'cancelado' => const Color(0xFFEF4444),
      _ => AppColors.primary,
    };
  }

  String _statusLabel(String status) {
    return switch (status.toLowerCase()) {
      'aberto' => 'ABERTO',
      'aceito' => 'ACEITO',
      'emandamento' || 'em_andamento' => 'EM ANDAMENTO',
      'finalizado' => 'FINALIZADO',
      'cancelado' => 'CANCELADO',
      _ => status.toUpperCase(),
    };
  }

  String _nomeMes(int mes) {
    const meses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    return meses[mes - 1];
  }

  String _diaSemanaAbrev(int weekday) {
    const dias = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    return dias[weekday % 7];
  }

  String _labelSemana() {
    final fim = _semanaBase.add(const Duration(days: 6));
    return '${_semanaBase.day}/${_semanaBase.month} - ${fim.day}/${fim.month}';
  }

  bool _isHoje(DateTime date) {
    final hoje = DateTime.now();
    return date.day == hoje.day &&
        date.month == hoje.month &&
        date.year == hoje.year;
  }
}
