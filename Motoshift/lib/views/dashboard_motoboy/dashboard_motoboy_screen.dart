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

  // Score e saldo reais via dashboardMotoboy
  Widget _buildScoreSection(AuthService auth) {
    final score = (_dashData?['score'] as num?)?.toDouble() ?? auth.usuario?.score ?? 5.0;
    final saldo = (_dashData?['saldoAtual'] as num?)?.toDouble() ?? 0.0;
    final scoreStr = score.toStringAsFixed(2);
    final estrelasCheias = score.floor();

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
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
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    color: AppColors.onSurface,
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
                      color: AppColors.primary,
                      size: 16,
                    )),
                  ],
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
