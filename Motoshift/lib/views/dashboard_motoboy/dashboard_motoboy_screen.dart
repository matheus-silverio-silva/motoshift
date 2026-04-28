import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pedido_entity.dart';
import '../../models/turno.dart';
import '../../presentation/providers/pedido_provider.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_app_bar.dart';
import '../../widgets/kinetic_bottom_nav.dart';
import '../relatorio/relatorio_screen.dart';
import '../score/score_analise_screen.dart';

class DashboardMotoboyScreen extends StatefulWidget {
  const DashboardMotoboyScreen({super.key});

  @override
  State<DashboardMotoboyScreen> createState() => _DashboardMotoboyScreenState();
}

class _DashboardMotoboyScreenState extends State<DashboardMotoboyScreen> {
  NavItem _navItem = NavItem.dashboard;
  int _diaIndex = 0;
  Map<String, dynamic>? _dashData;

  final List<String> _dias = ['Hoje', 'Amanhã', 'Depois', 'Em 3d', 'Em 4d', 'Em 5d'];

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

    context.read<PedidoProvider>().carregarDisponiveis();
    context.read<TurnoProvider>().carregarMeusTurnos(id);

    try {
      final data = await api.dashboardMotoboy(id);
      if (mounted) setState(() => _dashData = data);
    } catch (_) {}
  }

  void _onNavChanged(NavItem item) {
    setState(() => _navItem = item);
    switch (item) {
      case NavItem.dashboard:
        break;
      case NavItem.turnos:
        Navigator.pushNamed(context, '/meus-turnos');
        break;
      case NavItem.carteira:
        Navigator.pushNamed(context, '/carteira');
        break;
      case NavItem.agenda:
        Navigator.pushNamed(context, '/agenda');
        break;
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
      body: ListView(
        padding: const EdgeInsets.only(top: 80, bottom: 120, left: 24, right: 24),
        children: [
          const SizedBox(height: 16),
          _buildScoreSection(auth),
          const SizedBox(height: 16),
          _buildMotoboyStats(),
          const SizedBox(height: 16),
          _buildRelatorioCard(),
          const SizedBox(height: 32),
          _buildDateFilters(),
          const SizedBox(height: 24),

          // Pedidos Disponíveis via API (RF03)
          _buildSectionHeader('Entregas Disponíveis', trailing: _filterButton()),
          const SizedBox(height: 16),
          _buildPedidosSection(),
          const SizedBox(height: 32),

          // Turnos Aceitos via API (RF05)
          _buildSectionHeader('Turnos Aceitos', trailing: _turnosCountBadge()),
          const SizedBox(height: 16),
          _buildTurnosAceitosSection(),
        ],
      ),
      bottomNavigationBar: KineticBottomNav(
        currentItem: _navItem,
        onItemSelected: _onNavChanged,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/historico'),
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        tooltip: 'Histórico',
        child: const Icon(Icons.history_rounded, color: Colors.white),
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
    final turnosFinalizadosMes =
        (_dashData?['turnosFinalizadosMes'] as num?)?.toInt() ?? 0;

    if (turnosFinalizadosMes < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conclua pelo menos 3 turnos para gerar sua análise.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    // Exibe loading
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
      final data = await api.buscarRelatorioMotoboy(id);
      if (!mounted) return;
      Navigator.of(context).pop(); // fecha loading
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
      Navigator.of(context).pop(); // fecha loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível gerar o relatório. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _scoreColor(double score) {
    if (score >= 4.0) return const Color(0xFF00875A);
    if (score >= 2.5) return const Color(0xFFF59E0B);
    return const Color(0xFFBA1A1A);
  }

  Future<void> _abrirAnaliseScore() async {
    final turnosFinalizados =
        (_dashData?['turnosFinalizadosMes'] as num?)?.toInt() ?? 0;

    if (turnosFinalizados == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Conclua seu primeiro turno para começar a construir seu score!'),
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
                  'Analisando seu score...',
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
      final data = await api.buscarAnaliseScore(id);
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScoreAnaliseScreen(
            scoreAtual: (data['scoreAtual'] as num).toDouble(),
            scoreAnterior: (data['scoreAnterior'] as num).toDouble(),
            variacao: (data['variacao'] as num).toDouble(),
            tendencia: data['tendencia'] as String,
            classificacao: data['classificacao'] as String,
            analise: data['analise'] as String,
            ultimaAtualizacao: data['ultimaAtualizacao'] as String,
            eventos: (data['eventos'] as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível gerar a análise. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Score e saldo reais via dashboardMotoboy
  Widget _buildScoreSection(AuthService auth) {
    final score = (_dashData?['score'] as num?)?.toDouble() ?? auth.usuario?.score ?? 5.0;
    final saldo = (_dashData?['saldoAtual'] as num?)?.toDouble() ?? 0.0;
    final scoreStr = score.toStringAsFixed(2);
    final estrelasCheias = score.floor();
    final scoreC = _scoreColor(score);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scoreC.withOpacity(0.2), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SCORE DE REPUTAÇÃO',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  scoreStr,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    color: scoreC,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ...List.generate(5, (i) => Icon(
                      i < estrelasCheias
                          ? Icons.star_rounded
                          : (i == estrelasCheias && score - estrelasCheias >= 0.5
                              ? Icons.star_half_rounded
                              : Icons.star_outline_rounded),
                      color: scoreC,
                      size: 16,
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _abrirAnaliseScore,
                  child: Row(
                    children: [
                      Text(
                        'Ver análise',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scoreC,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, size: 13, color: scoreC),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.kineticGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SALDO',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/carteira'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Carteira',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMotoboyStats() {
    final ganhosMensais     = (_dashData?['ganhosMensais']     as num?)?.toDouble() ?? 0.0;
    final turnosFinalizados = (_dashData?['turnosFinalizadosMes'] as num?)?.toInt()  ?? 0;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GANHOS DO MÊS',
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
                  'R\$ ${ganhosMensais.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00875A),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TURNOS NO MÊS',
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
                  '$turnosFinalizados',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: AppColors.onSurface,
                  ),
                ),
                const Text(
                  'concluídos',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateFilters() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _dias.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = i == _diaIndex;
          return GestureDetector(
            onTap: () => setState(() => _diaIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                _dias[i],
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Pedidos via PedidoProvider
  Widget _buildPedidosSection() {
    return Consumer<PedidoProvider>(
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
            provider.carregarDisponiveis();
          });
        }
        if (provider.pedidosDisponiveis.isEmpty) {
          return _emptyCard('Nenhuma entrega disponível no momento.');
        }
        return Column(
          children: provider.pedidosDisponiveis.map((p) => _buildPedidoCard(p, provider)).toList(),
        );
      },
    );
  }

  // Turnos aceitos via TurnoProvider
  Widget _buildTurnosAceitosSection() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        if (provider.carregando) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }
        final aceitos = provider.meusTurnos
            .where((t) => t.status == StatusTurno.aceito || t.status == StatusTurno.emAndamento)
            .toList();
        if (aceitos.isEmpty) {
          return _emptyCard('Nenhum turno aceito no momento.');
        }
        return Column(children: aceitos.map(_buildAcceptedCard).toList());
      },
    );
  }

  Widget _turnosCountBadge() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        final count = provider.meusTurnos
            .where((t) => t.status == StatusTurno.aceito || t.status == StatusTurno.emAndamento)
            .length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count Ativo${count != 1 ? 's' : ''}',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSecondaryContainer,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPedidoCard(PedidoEntity pedido, PedidoProvider provider) {
    final auth = context.read<AuthService>();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delivery_dining_rounded, color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pedido.tipoCarga.label,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      pedido.nomeCliente ?? 'Cliente #${pedido.clienteId}',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (pedido.valorEstimado != null)
                Text(
                  'R\$ ${pedido.valorEstimado!.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(pedido.enderecoOrigem,
                style: const TextStyle(fontFamily: 'Manrope', fontSize: 12, color: AppColors.onSurface),
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.flag_outlined, size: 16, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: Text(pedido.enderecoDestino,
                style: const TextStyle(fontFamily: 'Manrope', fontSize: 12, color: AppColors.onSurfaceVariant),
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              final motoboyId = auth.usuario?.id;
              if (motoboyId == null || pedido.id == null) return;
              final ok = await provider.aceitarPedido(pedido.id!, motoboyId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? 'Corrida aceita!' : (provider.erro ?? 'Erro ao aceitar')),
                backgroundColor: ok ? Colors.green : Colors.red,
              ));
              if (ok) provider.limparErro();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.kineticGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Aceitar Corrida',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedCard(Turno turno) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.task_alt_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(turno.titulo,
                    style: const TextStyle(
                        fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                Text('${turno.regiao} · ${turno.horarioFormatado}',
                    style: const TextStyle(
                        fontFamily: 'Manrope', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/meus-turnos'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Detalhes',
                style: TextStyle(fontFamily: 'Manrope', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Text(msg,
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, color: AppColors.onSurfaceVariant)),
      ),
    );
  }

  Widget _erroCard(String msg, {required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.onSurfaceVariant, size: 40),
          const SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Manrope', color: AppColors.onSurfaceVariant)),
          TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                fontFamily: 'Manrope', fontSize: 17, fontWeight: FontWeight.w800,
                letterSpacing: -0.5, color: AppColors.onSurface)),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _filterButton() => const Row(
        children: [
          Icon(Icons.filter_list_rounded, size: 16, color: AppColors.primary),
          SizedBox(width: 4),
          Text('Filtrar',
              style: TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ],
      );
}
