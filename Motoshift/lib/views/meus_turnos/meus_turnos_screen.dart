import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/carteira.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_app_bar.dart';
import '../../widgets/kinetic_bottom_nav.dart';

class MeusTurnosScreen extends StatefulWidget {
  const MeusTurnosScreen({super.key});

  @override
  State<MeusTurnosScreen> createState() => _MeusTurnosScreenState();
}

class _MeusTurnosScreenState extends State<MeusTurnosScreen> {
  Carteira? _carteira;

  // Filtros para turnos disponíveis
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
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    provider.carregarMeusTurnos(id);
    _carregarDisponiveis();

    try {
      final c = await api.buscarCarteira(id);
      if (mounted) setState(() => _carteira = c);
    } catch (_) {}
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
      body: Consumer<TurnoProvider>(
        builder: (context, provider, _) {
          final ativo = provider.meusTurnos
              .where((t) => t.status == StatusTurno.emAndamento)
              .firstOrNull;
          final proximos = provider.meusTurnos
              .where((t) =>
                  t.status == StatusTurno.aceito ||
                  t.status == StatusTurno.aberto)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 96, 24, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Meus Turnos',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  provider.carregando
                      ? 'Carregando...'
                      : '${proximos.length} turno(s) agendado(s)',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Botão de Sugestão Inteligente via IA
                _buildSugestoesButton(),
                const SizedBox(height: 24),

                // ── Turnos Disponíveis ───────────────────────────────
                _buildDisponiveisSection(provider, auth),
                const SizedBox(height: 32),

                // ── Turno Ativo + Bento ──────────────────────────────
                if (provider.carregando)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (provider.erro != null)
                  _erroCard(provider.erro!, onRetry: _carregar)
                else ...[
                  _buildBentoGrid(ativo, provider),
                  const SizedBox(height: 32),
                  if (proximos.isNotEmpty) ...[
                    const Text(
                      'Próximos Turnos',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...proximos.map((t) => _buildProximoCard(t, provider)),
                  ],
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: KineticBottomNav(
        currentItem: NavItem.turnos,
        onItemSelected: (item) {
          switch (item) {
            case NavItem.dashboard:
              Navigator.pop(context);
            case NavItem.turnos:
              break;
            case NavItem.carteira:
              Navigator.pushNamed(context, '/carteira');
            case NavItem.agenda:
              Navigator.pushNamed(context, '/agenda');
          }
        },
      ),
    );
  }

  // ── Disponíveis ──────────────────────────────────────────

  Widget _buildDisponiveisSection(TurnoProvider provider, AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Disponíveis',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            GestureDetector(
              onTap: _abrirFiltros,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasFilters
                      ? AppColors.primary
                      : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: _hasFilters
                          ? Colors.white
                          : AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _hasFilters ? 'Filtros ativos' : 'Filtrar',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _hasFilters
                            ? Colors.white
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_hasFilters) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _limparFiltros,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Filtros ativos — toque para limpar',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.close_rounded,
                      size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (provider.turnosDisponiveis.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.search_off_rounded,
                    size: 40,
                    color: AppColors.onSurfaceVariant.withOpacity(0.5)),
                const SizedBox(height: 8),
                Text(
                  _hasFilters
                      ? 'Nenhum turno encontrado com esses filtros.'
                      : 'Nenhum turno disponível no momento.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (_hasFilters) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _limparFiltros,
                    child: const Text('Limpar filtros'),
                  ),
                ],
              ],
            ),
          )
        else
          ...provider.turnosDisponiveis
              .take(5)
              .map((t) => _buildDisponivelCard(t, provider, auth)),
      ],
    );
  }

  Widget _buildDisponivelCard(
      Turno turno, TurnoProvider provider, AuthService auth) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  turno.titulo,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                'R\$ ${turno.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 13, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                turno.horarioFormatado,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.location_on_rounded,
                  size: 13, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  turno.regiao,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${turno.raioEntregaKm.toStringAsFixed(0)} km',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final motoboyId = auth.usuario?.id;
              if (motoboyId == null) return;
              final ok = await provider.aceitarTurno(turno.id!, motoboyId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Turno aceito com sucesso!'
                    : (provider.erro ?? 'Erro ao aceitar')),
                backgroundColor: ok ? const Color(0xFF00875A) : Colors.red,
              ));
              if (ok) _carregar();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: AppColors.kineticGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Aceitar turno',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
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

  // ── Filtros BottomSheet ──────────────────────────────────

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

  // ── Sugestões ────────────────────────────────────────────

  Widget _buildSugestoesButton() {
    return GestureDetector(
      onTap: _mostrarSugestoes,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.kineticGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.kineticShadow,
        ),
        child: const Row(
          children: [
            Text('✨', style: TextStyle(fontSize: 22)),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ver sugestões para mim',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'IA analisa seu perfil e recomenda os melhores turnos',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white70, size: 14),
          ],
        ),
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
      builder: (_) => _SugestoesSheet(motoboyId: motoboyId, api: api),
    );
  }

  // ── Bento Grid ───────────────────────────────────────────

  Widget _buildBentoGrid(Turno? ativo, TurnoProvider provider) {
    return Column(
      children: [
        if (ativo != null) ...[
          _buildAtivoCard(ativo, provider),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(child: _buildMapCard(ativo)),
            const SizedBox(width: 16),
            Expanded(child: _buildCarteiraSnapshot()),
          ],
        ),
      ],
    );
  }

  Widget _buildAtivoCard(Turno turno, TurnoProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.kineticGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delivery_dining_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            turno.titulo,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            'Início: ${turno.horarioFormatado.split(' - ').first} • ${turno.duracao.inHours}h totais',
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'EM ANDAMENTO',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.onPrimaryFixed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _statCol('Ganhos Est.',
                    'R\$ ${turno.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}'),
                _divider(),
                _statCol('Entregas', '${turno.totalEntregas ?? 0}'),
                _divider(),
                _statCol('Km Percorrido',
                    '${turno.distanciaPercorridaKm?.toStringAsFixed(1) ?? '-'} km'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final ok = await provider.finalizarTurno(turno.id!);
                    if (!mounted) return;
                    if (ok) {
                      await _mostrarDialogAvaliacao(turno);
                      _carregar();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(provider.erro ?? 'Erro ao finalizar'),
                        backgroundColor: Colors.red,
                      ));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: AppColors.kineticGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppColors.kineticShadow,
                    ),
                    child: const Text(
                      'Confirmar Conclusão',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () async {
                  final ok = await provider.cancelarTurno(turno.id!);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        ok ? 'Turno cancelado.' : (provider.erro ?? 'Erro')),
                    backgroundColor: ok ? Colors.orange : Colors.red,
                  ));
                  if (ok) _carregar();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Avaliação Dialog ─────────────────────────────────────

  Future<void> _mostrarDialogAvaliacao(Turno turno) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final motoboyId = auth.usuario?.id;
    if (motoboyId == null) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AvaliacaoDialog(
        turnoId: turno.id!,
        avaliadorId: motoboyId,
        avaliadoId: turno.lojistId,
        api: api,
      ),
    );
  }

  // ── Stat helpers ─────────────────────────────────────────

  Widget _statCol(String label, String value) {
    return Expanded(
      child: Column(
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
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.outlineVariant.withOpacity(0.30),
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildMapCard(Turno? ativo) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: AppColors.surfaceContainerHighest,
            child: const Icon(Icons.map_outlined,
                size: 48, color: AppColors.outlineVariant),
          ),
          Container(color: AppColors.primary.withOpacity(0.08)),
          if (ativo != null)
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      ativo.regiao.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
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
    );
  }

  Widget _buildCarteiraSnapshot() {
    final saldo = _carteira?.saldoAtual ?? 0.0;
    final meta = 500.0;
    final progresso = (saldo / meta).clamp(0.0, 1.0);

    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Saldo Atual',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.primary, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.onSurface,
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progresso,
              backgroundColor: AppColors.surfaceContainerHighest,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(progresso * 100).toStringAsFixed(0)}% DA META DIÁRIA',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProximoCard(Turno turno, TurnoProvider provider) {
    final isConfirmado = turno.status == StatusTurno.aceito;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isConfirmado
                      ? Icons.schedule_outlined
                      : Icons.event_repeat_outlined,
                  color: AppColors.secondary,
                  size: 20,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isConfirmado ? 'CONFIRMADO' : 'PENDENTE',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            turno.titulo,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatProximoData(turno.dataInicio, turno.dataFim),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                Text(
                  'R\$ ${turno.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  turno.regiao,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.onSurfaceVariant, size: 40),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Manrope', color: AppColors.onSurfaceVariant)),
          TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }

  String _formatProximoData(DateTime inicio, DateTime fim) {
    final agora = DateTime.now();
    final diff =
        inicio.difference(DateTime(agora.year, agora.month, agora.day));
    String dia;
    if (diff.inDays == 1) {
      dia = 'Amanhã';
    } else if (diff.inDays == 0) {
      dia = 'Hoje';
    } else {
      const semana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab'];
      dia = semana[inicio.weekday % 7];
    }
    return '$dia, ${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')} - ${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog de Avaliação
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
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Avalie este turno',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.onSurface,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Como foi sua experiência com o lojista?',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // Estrelas
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _nota;
              return GestureDetector(
                onTap: () => setState(() => _nota = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled
                        ? const Color(0xFFF59E0B)
                        : AppColors.outlineVariant,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // Campo de comentário
          TextField(
            controller: _comentarioCtrl,
            maxLength: 100,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Comentário opcional...',
              hintStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
              counterStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Agora não',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        GestureDetector(
          onTap: _nota > 0 && !_enviando ? _enviar : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: _nota > 0
                  ? AppColors.kineticGradient
                  : null,
              color: _nota == 0 ? AppColors.surfaceContainerHigh : null,
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
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _nota > 0
                          ? Colors.white
                          : AppColors.onSurfaceVariant,
                    ),
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
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
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
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Text(
                  'Filtrar Turnos',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.onLimpar();
                    Navigator.pop(context);
                  },
                  child: const Text('Limpar'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Horário
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: _timeChip(
                          label: _horarioFim ?? 'Fim',
                          onTap: () => _pickHorario(false),
                          active: _horarioFim != null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Dia da semana
                  _label('Dia da semana'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _dias.map((d) {
                      final selected = _diaSemana == d.$1;
                      return GestureDetector(
                        onTap: () => setState(() =>
                            _diaSemana = selected ? null : d.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            d.$2,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : AppColors.onSurface,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Raio máximo
                  Row(
                    children: [
                      Expanded(child: _label('Raio máximo de entrega')),
                      Switch(
                        value: _raioAtivo,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _raioAtivo = v),
                      ),
                    ],
                  ),
                  if (_raioAtivo) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _raioMax,
                            min: 2,
                            max: 30,
                            divisions: 14,
                            activeColor: AppColors.primary,
                            onChanged: (v) =>
                                setState(() => _raioMax = v),
                          ),
                        ),
                        Text(
                          '${_raioMax.toStringAsFixed(0)} km',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Ordenar por
                  _label('Ordenar por'),
                  const SizedBox(height: 8),
                  ..._ordens.map((o) => RadioListTile<String>(
                        title: Text(
                          o.$2,
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            color: AppColors.onSurface,
                          ),
                        ),
                        value: o.$1,
                        groupValue: _ordenarPor,
                        activeColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setState(() => _ordenarPor = v!),
                      )),
                ],
              ),
            ),
          ),
          // Botão Aplicar
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.kineticGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppColors.kineticShadow,
                ),
                child: const Text(
                  'Aplicar filtros',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
      ),
    );
  }

  Widget _timeChip({
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? AppColors.primary.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 14,
              color:
                  active ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.primary : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BottomSheet de Sugestão Inteligente (IA)
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
      if (mounted) setState(() { _sugestoes = texto; _carregando = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível carregar sugestões. Tente novamente.';
          _carregando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: const [
                Text('✨', style: TextStyle(fontSize: 22)),
                SizedBox(width: 8),
                Text(
                  'Sugestões para você',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Com base no seu histórico dos últimos 30 dias',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Fechar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
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
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Consultando a IA...',
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

    if (_erro != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.onSurfaceVariant, size: 48),
            const SizedBox(height: 12),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Manrope', color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _carregar, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Text(
        _sugestoes ?? '',
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          height: 1.65,
          color: AppColors.onSurface,
        ),
      ),
    );
  }
}
