import 'package:flutter/material.dart' hide StepState;
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/timeline_stepper.dart';

class TurnoLojistScreen extends StatefulWidget {
  const TurnoLojistScreen({super.key});

  @override
  State<TurnoLojistScreen> createState() => _TurnoLojistScreenState();
}

class _TurnoLojistScreenState extends State<TurnoLojistScreen> {
  bool _cancelando = false;
  Usuario? _motoboyUsuario;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final turno =
          ModalRoute.of(context)?.settings.arguments as Turno?;
      if (turno?.motoboyId != null) {
        _carregarMotoboy(turno!.motoboyId!);
      }
    });
  }

  Future<void> _carregarMotoboy(int motoboyId) async {
    try {
      final api = context.read<ApiService>();
      final usuario = await api.buscarUsuario(motoboyId);
      if (mounted) setState(() => _motoboyUsuario = usuario);
    } catch (_) {
      // silencia — exibe fallback com ID
    }
  }

  Future<void> _cancelar(Turno turno) async {
    if (turno.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar turno',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          'Deseja realmente cancelar este turno?',
          style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar',
                style: tsJakarta(13, FontWeight.w600,
                    color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar turno',
                style: tsJakarta(13, FontWeight.w700,
                    color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancelando = true);
    final ok =
        await context.read<TurnoProvider>().cancelarTurno(turno.id!);
    if (!mounted) return;
    setState(() => _cancelando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turno cancelado.'),
          backgroundColor: AppColors.error,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao cancelar turno. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final turno =
        ModalRoute.of(context)?.settings.arguments as Turno?;

    return AppScaffold(
      header: AppHeader.back(title: 'Turno'),
      body: turno == null
          ? const Center(child: Text('Turno não encontrado.'))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      _TurnoInfoCard(turno: turno),
                      const SizedBox(height: 12),
                      _GridInfo(turno: turno),
                      const SizedBox(height: 12),
                      _StatusTimeline(status: turno.status),
                      if (turno.motoboyId != null) ...[
                        const SizedBox(height: 12),
                        _MotoboyCard(
                          motoboyId: turno.motoboyId!,
                          nome: _motoboyUsuario?.nome,
                          nota: _motoboyUsuario?.score,
                        ),
                      ],
                    ],
                  ),
                ),
                _Footer(
                  turno: turno,
                  cancelando: _cancelando,
                  onCancelar: () => _cancelar(turno),
                ),
              ],
            ),
    );
  }
}

// ── Card principal do turno ───────────────────────────────────────────────────
class _TurnoInfoCard extends StatelessWidget {
  const _TurnoInfoCard({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(turno.status);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.delivery_dining_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(turno.titulo,
                    style: tsBricolage(15, FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(turno.regiao,
                    style: tsJakarta(11, FontWeight.w400,
                        color: AppColors.muted)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              turno.status.label,
              style: tsJakarta(10, FontWeight.w700, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(StatusTurno s) => switch (s) {
        StatusTurno.aberto => const Color(0xFF3B82F6),
        StatusTurno.aceito => AppColors.amber,
        StatusTurno.emAndamento => AppColors.teal,
        StatusTurno.finalizado => AppColors.good,
        StatusTurno.cancelado => AppColors.error,
      };
}

// ── Grid 2×2 de informações ───────────────────────────────────────────────────
class _GridInfo extends StatelessWidget {
  const _GridInfo({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.access_time_rounded, 'Horário', turno.horarioFormatado),
      (Icons.radar_rounded, 'Raio', '${turno.raioEntregaKm.toStringAsFixed(0)} km'),
      (Icons.attach_money_rounded, 'Valor',
          'R\$ ${turno.valorEstimado.toStringAsFixed(0)}'),
      (Icons.location_on_rounded, 'Região', turno.regiao),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: items
          .map((item) =>
              _GridTile(icon: item.$1, label: item.$2, value: item.$3))
          .toList(),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: AppColors.teal),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label.toUpperCase(),
                    style: tsJakarta(7.5, FontWeight.w700,
                        color: AppColors.muted)),
                Text(value,
                    style: tsJakarta(11, FontWeight.w700,
                        color: AppColors.ink),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timeline de status ────────────────────────────────────────────────────────
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final StatusTurno status;

  @override
  Widget build(BuildContext context) {
    StepState stepFor(StatusTurno required) {
      const order = [
        StatusTurno.aberto,
        StatusTurno.aceito,
        StatusTurno.emAndamento,
        StatusTurno.finalizado,
      ];
      final cur = order.indexOf(status);
      final req = order.indexOf(required);
      if (cur < 0 || req < 0) return StepState.pending;
      if (req < cur) return StepState.done;
      if (req == cur) return StepState.current;
      return StepState.pending;
    }

    if (status == StatusTurno.cancelado) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined,
                color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Text('Turno cancelado',
                style: tsJakarta(12, FontWeight.w700,
                    color: AppColors.error)),
          ],
        ),
      );
    }

    return TimelineStepper(steps: [
      TimelineStep(
        label: 'Publicado',
        subtitle: 'Turno disponível para motoboys',
        state: stepFor(StatusTurno.aberto),
      ),
      TimelineStep(
        label: 'Motoboy confirmado',
        subtitle: 'Aguardando início do turno',
        state: stepFor(StatusTurno.aceito),
      ),
      TimelineStep(
        label: 'Em andamento',
        subtitle: 'Motoboy realizando entregas',
        state: stepFor(StatusTurno.emAndamento),
      ),
      TimelineStep(
        label: 'Finalizado',
        subtitle: 'Turno concluído com sucesso',
        state: stepFor(StatusTurno.finalizado),
      ),
    ]);
  }
}

// ── Card do motoboy designado ─────────────────────────────────────────────────
class _MotoboyCard extends StatelessWidget {
  const _MotoboyCard({
    required this.motoboyId,
    this.nome,
    this.nota,
  });

  final int motoboyId;
  final String? nome;
  final double? nota;
  // TODO: endpoint GET /usuarios/{id} não retorna veículo — adicionar quando disponível

  @override
  Widget build(BuildContext context) {
    final nomeExibido = nome ?? 'Motoboy #$motoboyId';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.two_wheeler_rounded,
                color: AppColors.teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nomeExibido,
                    style: tsJakarta(12, FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (nota != null) ...[
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFF6A623), size: 12),
                      const SizedBox(width: 3),
                      Text(nota!.toStringAsFixed(1),
                          style: tsJakarta(10, FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      'Turno aceito',
                      style: tsJakarta(10, FontWeight.w400,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Contatar',
                  style: tsJakarta(11, FontWeight.w700,
                      color: AppColors.tealDeep)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer fixo ───────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer({
    required this.turno,
    required this.cancelando,
    required this.onCancelar,
  });
  final Turno turno;
  final bool cancelando;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final podeCancelar = turno.status == StatusTurno.aberto ||
        turno.status == StatusTurno.aceito;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.line, width: 1.5),
        ),
      ),
      child: podeCancelar
          ? GhostButton(
              label: cancelando ? 'Cancelando...' : 'Cancelar turno',
              danger: true,
              onPressed: cancelando ? null : onCancelar,
            )
          : Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Turno ${turno.status.label.toLowerCase()}',
                  style: tsJakarta(13, FontWeight.w600,
                      color: AppColors.muted),
                ),
              ),
            ),
    );
  }
}
