import 'package:flutter/material.dart' hide StepState;
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/desktop/info_tile_grid.dart';
import '../../widgets/timeline_stepper.dart';

/// Conteúdo do turno visto pelo lojista (tela 8), sem scaffold em volta.
///
/// Serve à rota `/turno-lojista` do mobile e ao painel direito do
/// master-detail do desktop, incluindo o cancelamento. [onCancelado] decide o
/// que acontece depois: `pop` no mobile, recarregar a lista no desktop.
class TurnoLojistaConteudo extends StatefulWidget {
  const TurnoLojistaConteudo({
    required this.turno,
    this.onCancelado,
    this.desktop = false,
    super.key,
  });

  final Turno turno;
  final VoidCallback? onCancelado;
  final bool desktop;

  @override
  State<TurnoLojistaConteudo> createState() => _TurnoLojistaConteudoState();
}

class _TurnoLojistaConteudoState extends State<TurnoLojistaConteudo> {
  bool _cancelando = false;
  Usuario? _motoboyUsuario;
  int? _motoboyCarregado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarMotoboy());
  }

  @override
  void didUpdateWidget(TurnoLojistaConteudo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No desktop o mesmo widget é reaproveitado quando a seleção muda, então
    // o entregador precisa ser recarregado — não basta buscar no initState.
    if (oldWidget.turno.motoboyId != widget.turno.motoboyId) {
      _sincronizarMotoboy();
    }
  }

  Future<void> _sincronizarMotoboy() async {
    final motoboyId = widget.turno.motoboyId;
    if (motoboyId == null) {
      if (mounted && _motoboyUsuario != null) {
        setState(() {
          _motoboyUsuario = null;
          _motoboyCarregado = null;
        });
      }
      return;
    }
    if (_motoboyCarregado == motoboyId) return;

    try {
      final api = context.read<ApiService>();
      final usuario = await api.buscarUsuario(motoboyId);
      if (!mounted) return;
      setState(() {
        _motoboyUsuario = usuario;
        _motoboyCarregado = motoboyId;
      });
    } catch (_) {
      // silencia — exibe fallback com ID
    }
  }

  Future<void> _cancelar() async {
    final turno = widget.turno;
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
                style: tsJakarta(13, FontWeight.w600, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar turno',
                style: tsJakarta(13, FontWeight.w700, color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancelando = true);
    final ok = await context.read<TurnoProvider>().cancelarTurno(turno.id!);
    if (!mounted) return;
    setState(() => _cancelando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turno cancelado.'),
          backgroundColor: AppColors.error,
        ),
      );
      widget.onCancelado?.call();
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
    final turno = widget.turno;
    final blocos = <Widget>[
      TurnoInfoCard(turno: turno),
      SizedBox(height: widget.desktop ? 16 : 12),
      if (widget.desktop)
        InfoTileGrid(itens: _infoDoTurno(turno))
      else
        _GridInfo(turno: turno),
      SizedBox(height: widget.desktop ? 16 : 12),
      _StatusTimeline(status: turno.status),
      if (turno.motoboyId != null) ...[
        const SizedBox(height: 12),
        _MotoboyCard(
          motoboyId: turno.motoboyId!,
          nome: _motoboyUsuario?.nome,
          nota: _motoboyUsuario?.score,
        ),
      ],
    ];

    if (widget.desktop) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: blocos,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Acao(
              turno: turno,
              cancelando: _cancelando,
              onCancelar: _cancelar,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: blocos,
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.line, width: 1.5),
            ),
          ),
          child: _Acao(
            turno: turno,
            cancelando: _cancelando,
            onCancelar: _cancelar,
          ),
        ),
      ],
    );
  }
}

// ── Card principal do turno ─────────────────────────────────────────────────
class TurnoInfoCard extends StatelessWidget {
  const TurnoInfoCard({required this.turno, super.key});
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
                    style:
                        tsBricolage(15, FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(turno.regiao,
                    style:
                        tsJakarta(11, FontWeight.w400, color: AppColors.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

// ── Grid 2×2 de informações ─────────────────────────────────────────────────

List<InfoTileData> _infoDoTurno(Turno turno) => [
      InfoTileData(
        icon: Icons.access_time_rounded,
        label: 'Horário',
        valor: turno.horarioFormatado,
      ),
      InfoTileData(
        icon: Icons.radar_rounded,
        label: 'Raio',
        valor: '${turno.raioEntregaKm.toStringAsFixed(0)} km',
      ),
      InfoTileData(
        icon: Icons.attach_money_rounded,
        label: 'Valor',
        valor: 'R\$ ${turno.valorEstimado.toStringAsFixed(0)}',
      ),
      InfoTileData(
        icon: Icons.location_on_rounded,
        label: 'Região',
        valor: turno.regiao,
      ),
    ];

class _GridInfo extends StatelessWidget {
  const _GridInfo({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: _infoDoTurno(turno)
          .map((item) =>
              _GridTile(icon: item.icon, label: item.label, value: item.valor))
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
                    style:
                        tsJakarta(7.5, FontWeight.w700, color: AppColors.muted)),
                Text(value,
                    style: tsJakarta(11, FontWeight.w700, color: AppColors.ink),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timeline de status ──────────────────────────────────────────────────────
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
            const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Text('Turno cancelado',
                style:
                    tsJakarta(12, FontWeight.w700, color: AppColors.error)),
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

// ── Card do motoboy designado ───────────────────────────────────────────────
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
                    style:
                        tsJakarta(12, FontWeight.w700, color: AppColors.ink)),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

// ── Ação ────────────────────────────────────────────────────────────────────
class _Acao extends StatelessWidget {
  const _Acao({
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

    if (podeCancelar) {
      return GhostButton(
        label: cancelando ? 'Cancelando...' : 'Cancelar turno',
        danger: true,
        onPressed: cancelando ? null : onCancelar,
      );
    }
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          'Turno ${turno.status.label.toLowerCase()}',
          style: tsJakarta(13, FontWeight.w600, color: AppColors.muted),
        ),
      ),
    );
  }
}
