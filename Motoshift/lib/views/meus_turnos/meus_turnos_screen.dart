import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../avaliacao/avaliacao_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/section_title.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';

class MeusTurnosScreen extends StatefulWidget {
  const MeusTurnosScreen({super.key});

  @override
  State<MeusTurnosScreen> createState() => _MeusTurnosScreenState();
}

class _MeusTurnosScreenState extends State<MeusTurnosScreen> {
  String? _fHorarioInicio;
  String? _fHorarioFim;
  int? _fDiaSemana;
  double? _fRaioMax;
  String _fOrdenarPor = 'valorAsc';

  bool get _hasFilters =>
      _fHorarioInicio != null ||
      _fHorarioFim != null ||
      _fDiaSemana != null ||
      _fRaioMax != null ||
      _fOrdenarPor != 'valorAsc';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final provider = context.read<TurnoProvider>();
    final id = auth.usuario?.id;
    if (id == null) return;

    provider.carregarMeusTurnos(id);
    _carregarDisponiveis();
  }

  Future<void> _carregarDisponiveis() async {
    final api = context.read<ApiService>();
    final provider = context.read<TurnoProvider>();

    if (_hasFilters) {
      try {
        final lista = await api.listarTurnosDisponiveisComFiltros(
          horarioInicio: _fHorarioInicio,
          horarioFim: _fHorarioFim,
          diaSemana: _fDiaSemana,
          raioMaxKm: _fRaioMax,
          ordenarPor: _fOrdenarPor == 'valorAsc' ? null : _fOrdenarPor,
        );
        provider.setDisponiveisExterno(lista);
      } catch (_) {
        provider.carregarDisponiveis();
      }
    } else {
      provider.carregarDisponiveis();
    }
  }

  void _limparFiltros() {
    setState(() {
      _fHorarioInicio = null;
      _fHorarioFim = null;
      _fDiaSemana = null;
      _fRaioMax = null;
      _fOrdenarPor = 'valorAsc';
    });
    _carregarDisponiveis();
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
        Navigator.pushReplacementNamed(context, AppRoutes.dashboardMotoboy);
      case 1:
        break;
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.carteira);
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
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
        currentIndex: 1,
        onTap: _onNav,
      ),
      body: Consumer<TurnoProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              // Sugestão IA banner
              _buildSugestoesBtn(),
              const SizedBox(height: 12),
              // Seção disponíveis com filtros
              _buildDisponiveisSection(provider, auth),
              // Turnos em andamento
              if (!provider.carregando) ...[
                const SizedBox(height: 8),
                _buildMeusTurnosSection(provider),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSugestoesBtn() {
    return GestureDetector(
      onTap: _mostrarSugestoes,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Text('✨', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ver sugestões para mim',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'IA analisa seu perfil e recomenda os melhores turnos',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 10,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white70, size: 13),
          ],
        ),
      ),
    );
  }

  Widget _buildDisponiveisSection(
      TurnoProvider provider, AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionTitle(
                title: 'Turnos disponíveis',
                action: _hasFilters ? null : null,
              ),
            ),
            GestureDetector(
              onTap: _abrirFiltros,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasFilters
                      ? AppColors.teal
                      : AppColors.surface3,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 14,
                        color: _hasFilters
                            ? Colors.white
                            : AppColors.muted),
                    const SizedBox(width: 4),
                    Text(
                      _hasFilters ? 'Ativos' : 'Filtrar',
                      style: tsJakarta(11, FontWeight.w700,
                          color: _hasFilters
                              ? Colors.white
                              : AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_hasFilters)
          GestureDetector(
            onTap: _limparFiltros,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded,
                      size: 13, color: AppColors.tealDeep),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Filtros ativos — toque para limpar',
                      style: tsJakarta(11, FontWeight.w600,
                          color: AppColors.tealDeep),
                    ),
                  ),
                  const Icon(Icons.close_rounded,
                      size: 13, color: AppColors.tealDeep),
                ],
              ),
            ),
          ),
        if (provider.turnosDisponiveis.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                _hasFilters
                    ? 'Nenhum turno encontrado com esses filtros.'
                    : 'Nenhum turno disponível no momento.',
                textAlign: TextAlign.center,
                style: tsJakarta(12, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ),
          )
        else
          ...provider.turnosDisponiveis
              .take(8)
              .map((t) => _buildDisponivelCard(t, provider, auth)),
      ],
    );
  }

  Widget _buildDisponivelCard(
      Turno turno, TurnoProvider provider, AuthService auth) {
    return ShiftCard(
      name: turno.titulo,
      meta: [
        turno.horarioFormatado,
        turno.regiao,
        '${turno.raioEntregaKm.toStringAsFixed(0)} km',
      ],
      value: 'R\$ ${turno.valorEstimado.toStringAsFixed(0)}',
      iconData: Icons.two_wheeler_outlined,
      trailing: GestureDetector(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.detalheTurno,
          arguments: turno,
        ),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            'Ver',
            style: tsJakarta(10, FontWeight.w700,
                color: Colors.white),
          ),
        ),
      ),
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.detalheTurno,
        arguments: turno,
      ),
    );
  }

  Widget _buildMeusTurnosSection(TurnoProvider provider) {
    final ativo = provider.meusTurnos
        .where((t) => t.status == StatusTurno.emAndamento)
        .firstOrNull;
    final proximos = provider.meusTurnos
        .where((t) =>
            t.status == StatusTurno.aceito ||
            t.status == StatusTurno.aberto)
        .toList();

    if (ativo == null && proximos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ativo != null) ...[
          SectionTitle(title: 'Turno em andamento'),
          _buildAtivoCard(ativo, provider),
        ],
        if (proximos.isNotEmpty) ...[
          SectionTitle(
            title: 'Próximos turnos',
            action: '${proximos.length} agendado(s)',
          ),
          ...proximos
              .take(3)
              .map((t) => ShiftCard(
                    name: t.titulo,
                    meta: [
                      _formatProximoData(t.dataInicio, t.dataFim),
                      t.regiao,
                    ],
                    value:
                        'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                    iconData: Icons.schedule_outlined,
                    pillLabel: t.status.label,
                    pillVariant: t.status == StatusTurno.aceito
                        ? PillVariant.teal
                        : PillVariant.ghost,
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.detalheTurno,
                      arguments: t,
                    ),
                  )),
        ],
      ],
    );
  }

  Widget _buildAtivoCard(Turno turno, TurnoProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.tealSoft, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.two_wheeler_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(turno.titulo,
                        style: tsJakarta(13, FontWeight.w700,
                            color: AppColors.ink)),
                    Text(turno.horarioFormatado,
                        style: tsJakarta(10.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const StatusPill(
                  label: 'Em andamento',
                  variant: PillVariant.amber,
                  leadingDot: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final ok =
                        await provider.finalizarTurno(turno.id!);
                    if (!mounted) return;
                    if (ok) {
                      await _mostrarDialogAvaliacao(turno);
                      _carregar();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              provider.erro ?? 'Erro ao finalizar'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'Confirmar conclusão',
                        style: tsJakarta(12, FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final ok =
                      await provider.cancelarTurno(turno.id!);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? 'Turno cancelado.'
                        : (provider.erro ?? 'Erro')),
                    backgroundColor:
                        ok ? Colors.orange : Colors.red,
                  ));
                  if (ok) _carregar();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: Text(
                    'Cancelar',
                    style: tsJakarta(12, FontWeight.w700,
                        color: AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogAvaliacao(Turno turno) async {
    final auth = context.read<AuthService>();
    final motoboyId = auth.usuario?.id;
    if (motoboyId == null) return;

    await Navigator.pushNamed(
      context,
      AppRoutes.avaliacao,
      arguments: AvaliacaoArgs(
        turnoId: turno.id!,
        avaliadorId: motoboyId,
        avaliadoId: turno.lojistId,
        nomeAvaliado: turno.titulo,
      ),
    );
  }

  void _abrirFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiltrosSheet(
        horarioInicio: _fHorarioInicio,
        horarioFim: _fHorarioFim,
        diaSemana: _fDiaSemana,
        raioMax: _fRaioMax,
        ordenarPor: _fOrdenarPor,
        onAplicar: (hi, hf, ds, raio, ord) {
          setState(() {
            _fHorarioInicio = hi;
            _fHorarioFim = hf;
            _fDiaSemana = ds;
            _fRaioMax = raio;
            _fOrdenarPor = ord;
          });
          _carregarDisponiveis();
        },
        onLimpar: _limparFiltros,
      ),
    );
  }

  void _mostrarSugestoes() {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final motoboyId = auth.usuario?.id;
    if (motoboyId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _SugestoesSheet(motoboyId: motoboyId, api: api),
    );
  }

  String _formatProximoData(DateTime inicio, DateTime fim) {
    final agora = DateTime.now();
    final diff = inicio
        .difference(DateTime(agora.year, agora.month, agora.day));
    String dia;
    if (diff.inDays == 1) dia = 'Amanhã';
    else if (diff.inDays == 0) dia = 'Hoje';
    else {
      const semana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
      dia = semana[inicio.weekday % 7];
    }
    return '$dia, ${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')} – ${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog de Avaliação
// TODO: remover após migração completa para AvaliacaoScreen
// ─────────────────────────────────────────────────────────────────────────────

class _AvaliacaoDialog extends StatefulWidget {
  final int turnoId;
  final int avaliadorId;
  final int avaliadoId;
  final ApiService api;

  const _AvaliacaoDialog({
    required this.turnoId,
    required this.avaliadorId,
    required this.avaliadoId,
    required this.api,
  });

  @override
  State<_AvaliacaoDialog> createState() => _AvaliacaoDialogState();
}

class _AvaliacaoDialogState extends State<_AvaliacaoDialog> {
  int _nota = 0;
  final _comentarioCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_nota == 0) return;
    setState(() => _enviando = true);
    try {
      await widget.api.registrarAvaliacao({
        'turnoId': widget.turnoId,
        'avaliadorId': widget.avaliadorId,
        'avaliadoId': widget.avaliadoId,
        'nota': _nota,
        if (_comentarioCtrl.text.trim().isNotEmpty)
          'comentario': _comentarioCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar avaliação.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Avalie este turno',
        style: tsBricolage(17, FontWeight.w800, color: AppColors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Como foi sua experiência com o lojista?',
            style: tsJakarta(12.5, FontWeight.w400,
                color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _nota;
              return GestureDetector(
                onTap: () => setState(() => _nota = i + 1),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: filled
                        ? AppColors.amber
                        : AppColors.line,
                    size: 34,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _comentarioCtrl,
            maxLength: 100,
            maxLines: 2,
            style: tsJakarta(13, FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Comentário opcional...',
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Agora não',
              style: tsJakarta(13, FontWeight.w600,
                  color: AppColors.muted)),
        ),
        GestureDetector(
          onTap: _nota > 0 && !_enviando ? _enviar : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              gradient: _nota > 0 ? AppColors.primaryGradient : null,
              color:
                  _nota == 0 ? AppColors.surface3 : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Enviar',
                    style: tsJakarta(13, FontWeight.w700,
                        color: _nota > 0
                            ? Colors.white
                            : AppColors.muted),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BottomSheet de Filtros
// ─────────────────────────────────────────────────────────────────────────────

class _FiltrosSheet extends StatefulWidget {
  final String? horarioInicio;
  final String? horarioFim;
  final int? diaSemana;
  final double? raioMax;
  final String ordenarPor;
  final void Function(String?, String?, int?, double?, String) onAplicar;
  final VoidCallback onLimpar;

  const _FiltrosSheet({
    required this.horarioInicio,
    required this.horarioFim,
    required this.diaSemana,
    required this.raioMax,
    required this.ordenarPor,
    required this.onAplicar,
    required this.onLimpar,
  });

  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  String? _horarioInicio;
  String? _horarioFim;
  int? _diaSemana;
  double _raioMax = 20.0;
  bool _raioAtivo = false;
  String _ordenarPor = 'valorAsc';

  static const _dias = [
    (1, 'Seg'), (2, 'Ter'), (3, 'Qua'),
    (4, 'Qui'), (5, 'Sex'), (6, 'Sáb'), (7, 'Dom'),
  ];

  static const _ordens = [
    ('valorAsc', 'Maior valor'),
    ('valorDesc', 'Menor valor'),
    ('raioAsc', 'Menor raio'),
    ('dataInicio', 'Mais cedo'),
  ];

  @override
  void initState() {
    super.initState();
    _horarioInicio = widget.horarioInicio;
    _horarioFim = widget.horarioFim;
    _diaSemana = widget.diaSemana;
    _raioAtivo = widget.raioMax != null;
    _raioMax = widget.raioMax ?? 20.0;
    _ordenarPor = widget.ordenarPor;
  }

  Future<void> _pickHorario(bool isInicio) async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (result != null) {
      final str =
          '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isInicio) _horarioInicio = str;
        else _horarioFim = str;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Filtrar Turnos',
                    style: tsBricolage(16, FontWeight.w800,
                        color: AppColors.ink)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.onLimpar();
                    Navigator.pop(context);
                  },
                  child: Text('Limpar',
                      style: tsJakarta(12, FontWeight.w600,
                          color: AppColors.teal)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Horário'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _timeChip(
                          label: _horarioInicio ?? 'Início',
                          onTap: () => _pickHorario(true),
                          active: _horarioInicio != null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _timeChip(
                          label: _horarioFim ?? 'Fim',
                          onTap: () => _pickHorario(false),
                          active: _horarioFim != null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _label('Dia da semana'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _dias.map((d) {
                      final sel = _diaSemana == d.$1;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _diaSemana = sel ? null : d.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.teal
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(d.$2,
                              style: tsJakarta(12, FontWeight.w700,
                                  color: sel
                                      ? Colors.white
                                      : AppColors.ink)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: _label('Raio máximo de entrega')),
                      Switch(
                        value: _raioAtivo,
                        activeColor: AppColors.teal,
                        onChanged: (v) =>
                            setState(() => _raioAtivo = v),
                      ),
                    ],
                  ),
                  if (_raioAtivo) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.teal,
                              inactiveTrackColor: AppColors.surface3,
                              thumbColor: AppColors.teal,
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: _raioMax,
                              min: 2,
                              max: 30,
                              divisions: 14,
                              onChanged: (v) =>
                                  setState(() => _raioMax = v),
                            ),
                          ),
                        ),
                        Text(
                          '${_raioMax.toStringAsFixed(0)} km',
                          style: tsJakarta(12, FontWeight.w700,
                              color: AppColors.teal),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _label('Ordenar por'),
                  const SizedBox(height: 8),
                  ..._ordens.map((o) => RadioListTile<String>(
                        title: Text(o.$2,
                            style: tsJakarta(13, FontWeight.w500)),
                        value: o.$1,
                        groupValue: _ordenarPor,
                        activeColor: AppColors.teal,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setState(() => _ordenarPor = v!),
                      )),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).padding.bottom + 16),
            child: GestureDetector(
              onTap: () {
                widget.onAplicar(
                  _horarioInicio,
                  _horarioFim,
                  _diaSemana,
                  _raioAtivo ? _raioMax : null,
                  _ordenarPor,
                );
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('Aplicar filtros',
                      style: tsJakarta(14, FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: tsJakarta(12.5, FontWeight.w700, color: AppColors.ink));

  Widget _timeChip({
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? AppColors.tealSoft
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.teal.withOpacity(0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_rounded,
                size: 13,
                color: active ? AppColors.teal : AppColors.muted),
            const SizedBox(width: 5),
            Text(label,
                style: tsJakarta(12, FontWeight.w700,
                    color: active ? AppColors.teal : AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BottomSheet de Sugestões IA
// ─────────────────────────────────────────────────────────────────────────────

class _SugestoesSheet extends StatefulWidget {
  final int motoboyId;
  final ApiService api;

  const _SugestoesSheet({required this.motoboyId, required this.api});

  @override
  State<_SugestoesSheet> createState() => _SugestoesSheetState();
}

class _SugestoesSheetState extends State<_SugestoesSheet> {
  String? _sugestoes;
  String? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
      _sugestoes = null;
    });
    try {
      final texto =
          await widget.api.buscarSugestoesTurnos(widget.motoboyId);
      if (mounted) setState(() {
        _sugestoes = texto;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _erro = 'Não foi possível carregar sugestões. Tente novamente.';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('✨', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Sugestões para você',
                  style: tsBricolage(16, FontWeight.w800,
                      color: AppColors.ink)),
            ]),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Com base no seu histórico dos últimos 30 dias',
              style: tsJakarta(11.5, FontWeight.w400,
                  color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20,
                MediaQuery.of(context).padding.bottom + 16),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                child: Center(
                  child: Text('Fechar',
                      style: tsJakarta(13, FontWeight.w700,
                          color: AppColors.ink)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_carregando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.teal),
            SizedBox(height: 14),
            Text('Consultando a IA...'),
          ],
        ),
      );
    }
    if (_erro != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.muted, size: 44),
            const SizedBox(height: 10),
            Text(_erro!,
                textAlign: TextAlign.center,
                style: tsJakarta(13, FontWeight.w400,
                    color: AppColors.muted)),
            const SizedBox(height: 14),
            TextButton(
                onPressed: _carregar,
                child: const Text('Tentar novamente')),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Text(
        _sugestoes ?? '',
        style: tsJakarta(13.5, FontWeight.w400,
            color: AppColors.text, height: 1.65),
      ),
    );
  }
}
