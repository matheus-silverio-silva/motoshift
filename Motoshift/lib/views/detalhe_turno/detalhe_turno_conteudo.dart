import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/desktop/info_tile_grid.dart';

/// Conteúdo do detalhe do turno (tela 6), sem nenhum scaffold em volta.
///
/// A mesma instância serve à rota `/detalhe-turno` do mobile e ao painel
/// direito do master-detail do desktop — inclusive a ação de aceitar, que é o
/// motivo real de não duplicar esta tela. Quem hospeda decide o que acontece
/// depois de aceitar, via [onAceito]: no mobile é um `pop`, no desktop é só
/// recarregar a lista.
class DetalheTurnoConteudo extends StatefulWidget {
  const DetalheTurnoConteudo({
    required this.turno,
    this.onAceito,
    this.desktop = false,
    super.key,
  });

  final Turno turno;

  /// Chamado depois de aceitar com sucesso.
  final VoidCallback? onAceito;

  /// `true` monta a versão do artboard desktop (cabeçalho maior, grid de 2
  /// colunas, ações em linha); `false` mantém a pilha vertical do mobile.
  final bool desktop;

  @override
  State<DetalheTurnoConteudo> createState() => _DetalheTurnoConteudoState();
}

class _DetalheTurnoConteudoState extends State<DetalheTurnoConteudo> {
  bool _aceitando = false;

  Future<void> _aceitar() async {
    final turno = widget.turno;
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
      widget.onAceito?.call();
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
    return widget.desktop ? _buildDesktop() : _buildMobile();
  }

  // ── Mobile — estrutura original da rota empilhada ─────────────────────────

  Widget _buildMobile() {
    final turno = widget.turno;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              MapaPlaceholder(regiao: turno.regiao, altura: 160),
              const SizedBox(height: 14),
              _InfoCard(turno: turno),
              const SizedBox(height: 12),
              _GridInfo(turno: turno),
              if (turno.descricao != null && turno.descricao!.isNotEmpty) ...[
                const SizedBox(height: 12),
                RequisitosCard(descricao: turno.descricao!),
              ],
            ],
          ),
        ),
        _FooterMobile(
          turno: turno,
          aceitando: _aceitando,
          onAceitar: _aceitar,
        ),
      ],
    );
  }

  // ── Desktop — painel direito do master-detail ────────────────────────────

  Widget _buildDesktop() {
    final turno = widget.turno;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CabecalhoDesktop(turno: turno),
          const SizedBox(height: 16),
          InfoTileGrid(itens: _infoDoTurno(turno)),
          const SizedBox(height: 16),
          Expanded(child: MapaPlaceholder(regiao: turno.regiao)),
          if (turno.descricao != null && turno.descricao!.isNotEmpty) ...[
            const SizedBox(height: 16),
            RequisitosCard(descricao: turno.descricao!),
          ],
          const SizedBox(height: 16),
          _AcoesDesktop(
            turno: turno,
            aceitando: _aceitando,
            onAceitar: _aceitar,
          ),
        ],
      ),
    );
  }
}

// ── Placeholder do mapa ──────────────────────────────────────────────────────

/// Área do mapa. Continua placeholder: a tela 18 (filtro por raio) é quem traz
/// o mapa de verdade, reaproveitando o MapaRaio que já existe.
class MapaPlaceholder extends StatelessWidget {
  const MapaPlaceholder({required this.regiao, this.altura, super.key});

  final String regiao;

  /// Altura fixa. Nulo deixa o widget preencher o espaço disponível.
  final double? altura;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
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
                const Icon(Icons.map_outlined, size: 40, color: AppColors.muted),
                const SizedBox(height: 6),
                Text(
                  'Mapa indisponível',
                  style: tsJakarta(10, FontWeight.w400, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      style:
                          tsJakarta(10, FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card de info principal (mobile) ─────────────────────────────────────────
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
                    style:
                        tsBricolage(15, FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(turno.regiao,
                    style:
                        tsJakarta(11, FontWeight.w400, color: AppColors.muted)),
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

// ── Cabeçalho do painel desktop ─────────────────────────────────────────────
class _CabecalhoDesktop extends StatelessWidget {
  const _CabecalhoDesktop({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    final horas = turno.duracao.inMinutes / 60;
    final porHora = horas > 0 ? turno.valorEstimado / horas : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  turno.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tsBricolage(20, FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  turno.regiao,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'R\$ ${turno.valorEstimado.toStringAsFixed(0)}',
                style: tsBricolage(26, FontWeight.w800, color: AppColors.teal),
              ),
              const SizedBox(height: 4),
              Text(
                porHora == null
                    ? '${_horasLabel(horas)} de turno'
                    : 'R\$ ${porHora.toStringAsFixed(0)}/h · ${_horasLabel(horas)} de turno',
                style: tsJakarta(11, FontWeight.w700, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _horasLabel(double horas) {
    if (horas == horas.roundToDouble()) {
      return '${horas.toStringAsFixed(0)} h';
    }
    return '${horas.toStringAsFixed(1).replaceAll('.', ',')} h';
  }
}

// ── Grid de informações ─────────────────────────────────────────────────────

List<InfoTileData> _infoDoTurno(Turno turno) {
  final durMin = turno.duracao.inMinutes;
  final durLabel = durMin >= 60
      ? '${(durMin / 60).floor()}h${(durMin % 60).toString().padLeft(2, '0')}min'
      : '${durMin}min';

  return [
    InfoTileData(
      icon: Icons.access_time_rounded,
      label: 'Horário',
      valor: turno.horarioFormatado,
    ),
    InfoTileData(
      icon: Icons.radar_rounded,
      label: 'Raio de entrega',
      valor: '${turno.raioEntregaKm.toStringAsFixed(0)} km',
    ),
    InfoTileData(
      icon: Icons.attach_money_rounded,
      label: 'Valor estimado',
      valor:
          'R\$ ${turno.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}',
    ),
    InfoTileData(
      icon: Icons.timelapse_rounded,
      label: 'Duração',
      valor: durLabel,
    ),
    if (turno.multiVaga)
      InfoTileData(
        icon: Icons.groups_rounded,
        label: 'Vagas',
        valor: '${turno.vagasRestantes} de ${turno.vagas} livres',
      ),
  ];
}

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

// ── Card de requisitos ──────────────────────────────────────────────────────
class RequisitosCard extends StatelessWidget {
  const RequisitosCard({required this.descricao, super.key});
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
              style: tsJakarta(11, FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(descricao,
              style: tsJakarta(12, FontWeight.w400, color: AppColors.muted)),
        ],
      ),
    );
  }
}

// ── Ações ───────────────────────────────────────────────────────────────────
class _FooterMobile extends StatelessWidget {
  const _FooterMobile({
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
          : _StatusInerte(turno: turno),
    );
  }
}

class _AcoesDesktop extends StatelessWidget {
  const _AcoesDesktop({
    required this.turno,
    required this.aceitando,
    required this.onAceitar,
  });
  final Turno turno;
  final bool aceitando;
  final VoidCallback onAceitar;

  @override
  Widget build(BuildContext context) {
    if (turno.status != StatusTurno.aberto) {
      return _StatusInerte(turno: turno);
    }
    return PrimaryButton(
      label: 'Aceitar turno',
      loading: aceitando,
      onPressed: onAceitar,
    );
  }
}

class _StatusInerte extends StatelessWidget {
  const _StatusInerte({required this.turno});
  final Turno turno;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
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
