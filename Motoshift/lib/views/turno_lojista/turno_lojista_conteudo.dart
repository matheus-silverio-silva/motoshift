import 'package:flutter/material.dart' hide StepState;
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/pendencias_provider.dart';
import '../../routes/abrir_avaliacao.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../perfil_publico/perfil_publico_screen.dart';
import '../../widgets/acoes_do_turno.dart';
import '../../widgets/desktop/info_tile_grid.dart';
import '../../widgets/mapa_turno.dart';
import '../../widgets/o_que_falta.dart';
import '../../widgets/timeline_stepper.dart';

/// Conteúdo do turno visto pelo lojista (tela 8), sem scaffold em volta.
///
/// Serve à rota `/turno-lojista` do mobile e ao painel direito do
/// master-detail do desktop. [onMudou] decide o que acontece depois de uma
/// ação que muda o turno — `pop` no mobile, recarregar a lista no desktop.
///
/// O parâmetro se chamava `onCancelado` porque cancelar era a única coisa que
/// o lojista podia fazer aqui. Agora ele também finaliza e avalia, e as três
/// pedem a mesma reação de quem hospeda.
class TurnoLojistaConteudo extends StatefulWidget {
  const TurnoLojistaConteudo({
    required this.turno,
    this.onMudou,
    this.desktop = false,
    super.key,
  });

  final Turno turno;
  final VoidCallback? onMudou;
  final bool desktop;

  @override
  State<TurnoLojistaConteudo> createState() => _TurnoLojistaConteudoState();
}

/// Um entregador do turno, do jeito que o card precisa dele.
typedef _Inscrito = ({int id, String nome, double? nota, String status});

class _TurnoLojistaConteudoState extends State<TurnoLojistaConteudo> {
  /// Todos os entregadores do turno, e não só `turno.motoboyId`.
  ///
  /// O campo do turno guarda um id só — o primeiro que aceitou. Num turno de
  /// três vagas o lojista via um entregador e nenhuma pista de que havia mais
  /// dois, nem como chegar ao perfil deles. `GET /turnos/{id}/inscritos`
  /// devolve a lista inteira com o status de cada inscrição.
  List<_Inscrito> _inscritos = const [];
  int? _turnoCarregado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarInscritos());
  }

  @override
  void didUpdateWidget(TurnoLojistaConteudo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No desktop o mesmo widget é reaproveitado quando a seleção muda, então
    // a lista precisa ser recarregada — não basta buscar no initState.
    if (oldWidget.turno.id != widget.turno.id) _sincronizarInscritos();
  }

  Future<void> _sincronizarInscritos() async {
    final turnoId = widget.turno.id;
    if (turnoId == null || _turnoCarregado == turnoId) return;

    final api = context.read<ApiService>();
    try {
      final lista = await api.turnos.listarInscritos(turnoId);
      // A nota vem do perfil público, uma consulta por inscrito. São poucos —
      // no máximo o número de vagas — e é a rota que a LGPD deixou de pé.
      final inscritos = await Future.wait(lista.map((m) async {
        final id = (m['motoboyId'] as num).toInt();
        final nome = m['nome'] as String? ?? 'Entregador';
        double? nota;
        try {
          nota = (await api.usuarios.buscarPerfilPublico(id)).score;
        } catch (_) {
          nota = null;
        }
        return (
          id: id,
          nome: nome,
          nota: nota,
          status: m['status'] as String? ?? '',
        );
      }));

      if (!mounted) return;
      setState(() {
        _inscritos = inscritos;
        _turnoCarregado = turnoId;
      });
    } catch (_) {
      // Turno legado, sem inscrições: cai no id solto do turno, que é o que
      // existia antes das vagas. Sem isto o lojista deixaria de ver o
      // entregador que ele já via.
      final motoboyId = widget.turno.motoboyId;
      if (!mounted || motoboyId == null) return;
      setState(() {
        _inscritos = [
          (id: motoboyId, nome: 'Motoboy #$motoboyId', nota: null, status: '')
        ];
        _turnoCarregado = turnoId;
      });
    }
  }

  /// O lojista ainda deve nota a alguém deste turno?
  bool get _podeAvaliar => context
      .watch<PendenciasProvider>()
      .avaliacoesDoTurno(widget.turno.id)
      .isNotEmpty;

  Future<void> _avaliar(Turno turno) async {
    await abrirAvaliacao(context, turno);
    if (!mounted) return;
    context
        .read<PendenciasProvider>()
        .carregar(context.read<AuthService>().usuario);
  }

  /// O que dizer embaixo do nome do entregador.
  ///
  /// O card dizia "Turno aceito" para todo mundo, inclusive depois de o turno
  /// ter sido finalizado ou de a inscrição daquela pessoa ter sido cancelada.
  String _rotuloDaInscricao(String statusInscricao, StatusTurno statusTurno) {
    if (statusInscricao.toUpperCase() == 'FINALIZADO' ||
        statusTurno == StatusTurno.finalizado) {
      return 'Turno concluído';
    }
    if (statusTurno == StatusTurno.emAndamento) return 'Em andamento';
    if (statusTurno == StatusTurno.cancelado) return 'Turno cancelado';
    return 'Turno aceito';
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
      // O que falta fica antes do mapa: é a única parte da tela que pede uma
      // ação, e depois do turno encerrado é a razão de o lojista ter aberto
      // esta tela. Some sozinho quando não há pendência.
      OQueFalta(
        turno: turno,
        margem: EdgeInsets.only(bottom: widget.desktop ? 16 : 12),
      ),
      MapaTurno(turno: turno, altura: widget.desktop ? 220 : 170),
      SizedBox(height: widget.desktop ? 16 : 12),
      _StatusTimeline(status: turno.status),
      for (final inscrito in _inscritos) ...[
        const SizedBox(height: 12),
        _MotoboyCard(
          motoboyId: inscrito.id,
          nome: inscrito.nome,
          nota: inscrito.nota,
          statusLabel: _rotuloDaInscricao(inscrito.status, turno.status),
          onAvaliar: _podeAvaliar ? () => _avaliar(turno) : null,
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
            AcoesDoTurno(
              turno: turno,
              emLinha: true,
              onMudou: widget.onMudou,
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
          child: AcoesDoTurno(turno: turno, onMudou: widget.onMudou),
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
        StatusTurno.expirado => AppColors.muted,
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
    required this.statusLabel,
    this.nome,
    this.nota,
    this.onAvaliar,
  });

  final int motoboyId;
  final String? nome;
  final double? nota;

  /// O estado desta inscrição, em palavras — "Turno aceito", "Em andamento",
  /// "Turno concluído".
  final String statusLabel;

  /// Só existe quando o turno acabou e a nota deste entregador ainda falta.
  final VoidCallback? onAvaliar;
  // GET /usuarios/{id} de outra conta já traz veiculoModelo e veiculoCor no
  // perfil público; mostrá-los aqui é mudança de layout (e de golden), não de
  // contrato.

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
                      statusLabel,
                      style: tsJakarta(10, FontWeight.w400,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Era "Contatar", com onTap vazio. A saída óbvia seria abrir o
          // telefone do entregador — mas o PerfilPublicoResponse não devolve
          // telefone nem e-mail, e não por esquecimento: foram cortados por
          // LGPD. Expor o número só para este botão desfaria essa decisão.
          if (onAvaliar != null) ...[
            _BotaoDoCard(rotulo: 'Avaliar', destaque: true, onTap: onAvaliar!),
            const SizedBox(width: 6),
          ],
          _BotaoDoCard(
            rotulo: 'Ver perfil',
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.perfilPublico,
              arguments: PerfilPublicoArgs(usuarioId: motoboyId, nome: nome),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão pequeno do card do entregador.
class _BotaoDoCard extends StatelessWidget {
  const _BotaoDoCard({
    required this.rotulo,
    required this.onTap,
    this.destaque = false,
  });

  final String rotulo;
  final VoidCallback onTap;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: destaque ? AppColors.amberSoft : AppColors.tealSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(rotulo,
            style: tsJakarta(11, FontWeight.w700,
                color: destaque
                    ? AppColors.onTertiaryContainer
                    : AppColors.tealDeep)),
      ),
    );
  }
}
