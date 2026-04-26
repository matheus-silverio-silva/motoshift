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

    try {
      final c = await api.buscarCarteira(id);
      if (mounted) setState(() => _carteira = c);
    } catch (_) {}
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

                if (provider.carregando)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: CircularProgressIndicator(color: AppColors.primary),
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
          if (item == NavItem.dashboard) Navigator.pop(context);
          if (item == NavItem.carteira) Navigator.pushNamed(context, '/carteira');
        },
      ),
    );
  }

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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok ? 'Turno finalizado!' : (provider.erro ?? 'Erro')),
                      backgroundColor: ok ? const Color(0xFF00875A) : Colors.red,
                    ));
                    if (ok) _carregar();
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
                    content: Text(ok ? 'Turno cancelado.' : (provider.erro ?? 'Erro')),
                    backgroundColor: ok ? Colors.orange : Colors.red,
                  ));
                  if (ok) _carregar();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
