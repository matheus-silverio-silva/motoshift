import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';

/// Saldo que o backend ainda não devolve.
///
/// A tela 21 separa disponível de bloqueado, mas em `main` não existe carteira
/// de lojista: `CarteiraController` é do motoboy (`/carteira/{motoboyId}`) e
/// `CarteiraService.buscar` cria uma carteira zerada para qualquer id que
/// receba — chamar com o id do lojista devolveria R$ 0,00 sem significado.
///
/// Então os campos existem, ficam prontos para receber `saldoDisponivel` e
/// `saldoBloqueado` assim que o endpoint aparecer, e até lá a tela diz que o
/// dado não está disponível em vez de mostrar um número inventado.
class SaldoLojista {
  const SaldoLojista({this.disponivel, this.bloqueado});

  final double? disponivel;
  final double? bloqueado;

  bool get indisponivel => disponivel == null && bloqueado == null;

  double? get total => (disponivel == null || bloqueado == null)
      ? null
      : disponivel! + bloqueado!;
}

/// Tela 21 — saldo do lojista, separando disponível de bloqueado.
class SaldoLojistaScreen extends StatefulWidget {
  const SaldoLojistaScreen({super.key});

  @override
  State<SaldoLojistaScreen> createState() => _SaldoLojistaScreenState();
}

class _SaldoLojistaScreenState extends State<SaldoLojistaScreen> {
  /// Sem endpoint, nasce vazio. Trocar por uma chamada de API é a única
  /// mudança necessária quando o backend expuser a carteira do lojista.
  final SaldoLojista _saldo = const SaldoLojista();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final id = auth.usuario?.id;
    if (id == null) return;
    // Os turnos alimentam a lista de valores comprometidos — esse dado existe.
    context.read<TurnoProvider>().carregarTurnosLojista(id);
  }

  /// Turnos que já têm entregador e ainda não foram encerrados: é o dinheiro
  /// que o lojista assumiu e ainda vai pagar.
  List<Turno> _comprometidos(List<Turno> turnos) => turnos
      .where((t) =>
          t.status == StatusTurno.aceito ||
          t.status == StatusTurno.emAndamento)
      .toList()
    ..sort((a, b) => a.dataInicio.compareTo(b.dataInicio));

  /// Soma o que cada turno vai custar. `valorEstimado` é por entregador — o
  /// backend credita esse valor a cada um (ver `TurnoService.creditarCarteira`).
  double _custo(Turno t) =>
      t.valorEstimado * (t.vagasPreenchidas > 0 ? t.vagasPreenchidas : 1);

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Saldo'),
      desktopTitle: 'Saldo',
      desktopSubtitle: 'Disponível, bloqueado e turnos comprometidos',
      desktopSelectedRoute: AppRoutes.carteira,
      desktopBody: _buildDesktop(),
      body: _buildMobile(),
    );
  }

  Widget _buildMobile() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        final comprometidos = _comprometidos(provider.turnosLojista);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildCardSaldo(),
            const SizedBox(height: 16),
            _buildComprometidos(provider, comprometidos),
          ],
        );
      },
    );
  }

  Widget _buildDesktop() {
    return Consumer<TurnoProvider>(
      builder: (context, provider, _) {
        final comprometidos = _comprometidos(provider.turnosLojista);
        return ContentGrid(
          children: [
            GridCol(span: 5, child: _buildCardSaldo()),
            GridCol(
              span: 7,
              child: _buildComprometidos(provider, comprometidos),
            ),
          ],
        );
      },
    );
  }

  // ── Bloco do saldo ───────────────────────────────────────────────────────

  Widget _buildCardSaldo() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Color(0x12FFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Saldo disponível',
                    style: tsJakarta(11, FontWeight.w600,
                        color: const Color(0xFFBFE5E3))),
                const SizedBox(height: 6),
                Text(
                  _saldo.disponivel == null
                      ? '—'
                      : 'R\$ ${_saldo.disponivel!.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: tsBricolage(32, FontWeight.w800,
                      color: const Color(0xFFFFFFFF)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _quadroValor('BLOQUEADO', _saldo.bloqueado),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _quadroValor('TOTAL', _saldo.total)),
                  ],
                ),
                if (_saldo.indisponivel) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x24FFFFFF),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 17, color: Color(0xFFBFE5E3)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'A carteira do lojista ainda não é exposta pela '
                            'API. Os valores aparecem aqui assim que o '
                            'endpoint existir.',
                            style: tsJakarta(11, FontWeight.w400,
                                color: const Color(0xFFBFE5E3), height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quadroValor(String rotulo, double? valor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo,
              style: tsJakarta(9, FontWeight.w700,
                      color: const Color(0xFFBFE5E3))
                  .copyWith(letterSpacing: 9 * .06)),
          const SizedBox(height: 2),
          Text(
            valor == null ? '—' : 'R\$ ${valor.toStringAsFixed(0)}',
            style: tsBricolage(16, FontWeight.w800,
                color: const Color(0xFFFFFFFF)),
          ),
        ],
      ),
    );
  }

  // ── Turnos comprometidos ─────────────────────────────────────────────────

  Widget _buildComprometidos(TurnoProvider provider, List<Turno> turnos) {
    final total = turnos.fold<double>(0, (a, t) => a + _custo(t));

    return PanelCard(
      title: 'Comprometido em turnos',
      subtitle: 'Turnos com entregador aceito e ainda não encerrados',
      padding: const EdgeInsets.all(18),
      gap: 12,
      trailing: turnos.isEmpty
          ? null
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${turnos.length} ${turnos.length == 1 ? 'turno' : 'turnos'}',
                style: tsJakarta(9.5, FontWeight.w700,
                    color: AppColors.muted),
              ),
            ),
      child: provider.carregando
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.teal),
              ),
            )
          : turnos.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('Nenhum turno comprometido no momento.',
                        style: tsJakarta(12.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in turnos) _buildLinha(t),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Total comprometido',
                              style: tsJakarta(12.5, FontWeight.w700,
                                  color: AppColors.text)),
                        ),
                        Text('R\$ ${total.toStringAsFixed(0)}',
                            style: tsBricolage(15, FontWeight.w800,
                                color: AppColors.ink)),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _buildLinha(Turno t) {
    final emAndamento = t.status == StatusTurno.emAndamento;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: emAndamento
                    ? AppColors.amberSoft
                    : AppColors.tealSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                emAndamento
                    ? Icons.lock_clock_outlined
                    : Icons.lock_outline_rounded,
                size: 17,
                color: emAndamento
                    ? AppColors.onTertiaryContainer
                    : AppColors.tealDeep,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tsJakarta(12.5, FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                    '${t.regiao} · '
                    '${t.multiVaga ? '${t.vagasPreenchidas} de ${t.vagas} vagas' : emAndamento ? 'em andamento' : 'aceito'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('R\$ ${_custo(t).toStringAsFixed(0)}',
                style:
                    tsBricolage(14, FontWeight.w800, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}
