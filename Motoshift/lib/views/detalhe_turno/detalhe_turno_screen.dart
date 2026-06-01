import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';

class DetalheTurnoScreen extends StatefulWidget {
  const DetalheTurnoScreen({super.key});

  @override
  State<DetalheTurnoScreen> createState() => _DetalheTurnoScreenState();
}

class _DetalheTurnoScreenState extends State<DetalheTurnoScreen> {
  bool _aceitando = false;

  Future<void> _aceitar(Turno turno) async {
    final auth = context.read<AuthService>();
    final provider = context.read<TurnoProvider>();
    final motoboyId = auth.usuario?.id;
    if (motoboyId == null || turno.id == null) return;

    setState(() => _aceitando = true);
    final ok = await provider.aceitarTurno(turno.id!, motoboyId);
    if (!mounted) return;
    setState(() => _aceitando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turno aceito com sucesso!'),
          backgroundColor: AppColors.good,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Não foi possível aceitar o turno.'),
          backgroundColor: AppColors.error,
        ),
      );
      provider.limparErro();
    }
  }

  @override
  Widget build(BuildContext context) {
    final turno =
        ModalRoute.of(context)?.settings.arguments as Turno?;

    return AppScaffold(
      header: AppHeader.back(title: 'Detalhes do Turno'),
      body: turno == null
          ? const Center(child: Text('Turno não encontrado.'))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      _MapPlaceholder(regiao: turno.regiao),
                      const SizedBox(height: 14),
                      _InfoCard(turno: turno),
                      const SizedBox(height: 12),
                      _GridInfo(turno: turno),
                      if (turno.descricao != null &&
                          turno.descricao!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _RequisitosCard(descricao: turno.descricao!),
                      ],
                    ],
                  ),
                ),
                _Footer(
                  turno: turno,
                  aceitando: _aceitando,
                  onAceitar: () => _aceitar(turno),
                ),
              ],
            ),
    );
  }
}

// ── Placeholder do mapa ────────────────────────────────────────────────────────
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.regiao});
  final String regiao;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined,
                    size: 40, color: AppColors.muted),
                const SizedBox(height: 6),
                Text(
                  'Mapa indisponível',
                  style:
                      tsJakarta(10, FontWeight.w400, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.ink.withOpacity(0.75),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(regiao,
                      style: tsJakarta(10, FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card de info principal ─────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
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
            child: const Icon(Icons.storefront_rounded,
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
          Text(
            'R\$ ${turno.valorEstimado.toStringAsFixed(0)}',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.teal),
          ),
        ],
      ),
    );
  }
}

// ── Grid 2×2 de informações ────────────────────────────────────────────────────
class _GridInfo extends StatelessWidget {
  const _GridInfo({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    final durMin = turno.duracao.inMinutes;
    final durLabel = durMin >= 60
        ? '${(durMin / 60).floor()}h${(durMin % 60).toString().padLeft(2, '0')}min'
        : '${durMin}min';

    final items = [
      (Icons.access_time_rounded, 'Horário', turno.horarioFormatado),
      (Icons.radar_rounded, 'Raio de entrega',
          '${turno.raioEntregaKm.toStringAsFixed(0)} km'),
      (Icons.attach_money_rounded, 'Valor estimado',
          'R\$ ${turno.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}'),
      (Icons.timelapse_rounded, 'Duração', durLabel),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: items
          .map((item) => _GridTile(icon: item.$1, label: item.$2, value: item.$3))
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

// ── Card de requisitos ────────────────────────────────────────────────────────
class _RequisitosCard extends StatelessWidget {
  const _RequisitosCard({required this.descricao});
  final String descricao;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Descrição',
              style:
                  tsJakarta(11, FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(descricao,
              style: tsJakarta(12, FontWeight.w400, color: AppColors.muted)),
        ],
      ),
    );
  }
}

// ── Footer fixo com botão de aceitar ─────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer({
    required this.turno,
    required this.aceitando,
    required this.onAceitar,
  });
  final Turno turno;
  final bool aceitando;
  final VoidCallback onAceitar;

  @override
  Widget build(BuildContext context) {
    final podeAceitar = turno.status == StatusTurno.aberto;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.line, width: 1.5),
        ),
      ),
      child: podeAceitar
          ? PrimaryButton(
              label: 'Aceitar turno',
              loading: aceitando,
              onPressed: onAceitar,
            )
          : Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppColors.line, width: 1.5),
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
