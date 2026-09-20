import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/resumo_financeiro.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';

/// Tela 21 — saldo do lojista, separando disponível de bloqueado.
///
/// Até esta versão a tela dizia que o dado "não está disponível": não havia
/// carteira de lojista no backend, e `CarteiraService.buscar` criava uma
/// zerada para qualquer id, então chamar com o id do lojista devolveria R$ 0,00
/// sem significado. Agora o lojista tem carteira de verdade — é dela que sai a
/// reserva de cada turno publicado — e a tela lê `/api/carteira/resumo`.
///
/// O número de "comprometido" vem ao lado da lista que o explica de propósito:
/// os dois são leituras do mesmo fato, e se discordarem isso aparece aqui em
/// vez de ficar escondido.
class SaldoLojistaScreen extends StatefulWidget {
  const SaldoLojistaScreen({super.key});

  @override
  State<SaldoLojistaScreen> createState() => _SaldoLojistaScreenState();
}

class _SaldoLojistaScreenState extends State<SaldoLojistaScreen> {
  ResumoFinanceiro? _resumo;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await context.read<ApiService>().carteira.buscarResumo();
      if (mounted) setState(() => _resumo = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Erro ao carregar o saldo.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _recarregar() async {
    final creditou = await Navigator.of(context).pushNamed(AppRoutes.recarga);
    if (creditou == true) _carregar();
  }

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
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildCardSaldo(),
          const SizedBox(height: 16),
          _buildComprometidos(),
        ],
      ),
    );
  }

  Widget _buildDesktop() {
    return ContentGrid(
      children: [
        GridCol(span: 5, child: _buildCardSaldo()),
        GridCol(span: 7, child: _buildComprometidos()),
      ],
    );
  }

  // ── Bloco do saldo ───────────────────────────────────────────────────────

  Widget _buildCardSaldo() {
    final r = _resumo;
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
                  r == null ? '—' : _moeda(r.disponivel),
                  key: const Key('saldo-lojista-disponivel'),
                  style: tsBricolage(32, FontWeight.w800,
                      color: const Color(0xFFFFFFFF)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _quadroValor('BLOQUEADO', r?.bloqueado)),
                    const SizedBox(width: 8),
                    Expanded(child: _quadroValor('TOTAL', r?.saldoTotal)),
                  ],
                ),
                const SizedBox(height: 14),
                if (_erro != null)
                  _avisoDeErro(_erro!)
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('saldo-lojista-adicionar'),
                      onPressed: _carregando ? null : _recarregar,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Adicionar saldo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: AppColors.onTertiary,
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
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

  Widget _avisoDeErro(String mensagem) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 17, color: Color(0xFFBFE5E3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mensagem,
                style: tsJakarta(11, FontWeight.w400,
                    color: const Color(0xFFBFE5E3), height: 1.45)),
          ),
        ],
      ),
    );
  }

  // ── Turnos comprometidos ─────────────────────────────────────────────────

  /// As reservas abertas, vindas do próprio extrato.
  ///
  /// A versão anterior desta lista somava `valorEstimado × vagas preenchidas`
  /// dos turnos aceitos — uma estimativa do cliente sobre o que o backend faria.
  /// Agora o número é o que está de fato bloqueado na carteira, turno a turno.
  Widget _buildComprometidos() {
    final reservas = _resumo?.reservasAbertas ?? const <ReservaAberta>[];
    final total = _resumo?.comprometido ?? 0;

    return PanelCard(
      title: 'Comprometido em turnos',
      subtitle: 'Valor reservado para turnos publicados e ainda não encerrados',
      padding: const EdgeInsets.all(18),
      gap: 12,
      trailing: reservas.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${reservas.length} ${reservas.length == 1 ? 'turno' : 'turnos'}',
                style: tsJakarta(9.5, FontWeight.w700, color: AppColors.muted),
              ),
            ),
      child: _carregando
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.teal),
              ),
            )
          : reservas.isEmpty
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
                    for (final r in reservas) _buildLinha(r),
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
                            key: const Key('saldo-lojista-comprometido'),
                            style: tsBricolage(15, FontWeight.w800,
                                color: AppColors.ink)),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _buildLinha(ReservaAberta r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pushNamed(
          AppRoutes.turnoLojista,
          arguments: {'turnoId': r.turnoId},
        ),
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
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    size: 17, color: AppColors.tealDeep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(12.5, FontWeight.w700,
                            color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text('Reservado na publicação',
                        style: tsJakarta(10.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('R\$ ${r.valor.toStringAsFixed(0)}',
                  style:
                      tsBricolage(14, FontWeight.w800, color: AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}
