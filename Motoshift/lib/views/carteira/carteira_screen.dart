import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/carteira.dart';
import '../../models/transacao.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/app_topbar.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/section_title.dart';
import '../../widgets/wallet_widgets.dart';

class CarteiraScreen extends StatefulWidget {
  const CarteiraScreen({super.key, this.agora});

  /// Fixa o "agora" do extrato. So os testes passam isto — e o padrao e o
  /// mesmo das outras telas com golden (AgendaScreen, dashboards,
  /// MeusTurnosScreen, PerfilScreen).
  final DateTime? agora;

  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> {
  Carteira? _carteira;
  bool _carregando = false;
  String? _erro;

  /// Filtro do extrato no desktop: todos | entradas | saques.
  String _filtroExtrato = 'todos';

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

    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final c = await api.carteira.buscarCarteira(id);
      if (mounted) setState(() => _carteira = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Erro ao carregar carteira.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _solicitarSaque() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Transferir Saldo',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Valor (R\$)',
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: tsJakarta(13, FontWeight.w600,
                    color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirmar',
                style: tsJakarta(13, FontWeight.w700,
                    color: AppColors.teal)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final valor = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valor inválido.')),
      );
      return;
    }

    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    try {
      await api.carteira.solicitarSaque(id, valor);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transferência solicitada com sucesso!'),
          backgroundColor: AppColors.good,
        ));
        _carregar();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erro ao solicitar transferência.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _onNav(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacementNamed(
            context, AppRoutes.dashboardMotoboy);
      case 1:
        Navigator.pushReplacementNamed(
            context, AppRoutes.turnosDisponiveis);
      case 2:
        break;
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(
        title: 'Carteira Digital',
        onBack: () => Navigator.pushReplacementNamed(
            context, AppRoutes.dashboardMotoboy),
      ),
      bottomNav: AppBottomNav(
        userType: UserType.motoboy,
        currentIndex: 2,
        onTap: _onNav,
      ),
      desktopTitle: 'Carteira digital',
      desktopSubtitle: _subtituloDesktop(),
      desktopSelectedRoute: AppRoutes.carteira,
      desktopPrimaryAction: TopbarPrimaryButton(
        label: 'Sacar via Pix',
        icon: Icons.qr_code_rounded,
        onTap: _solicitarSaque,
      ),
      desktopBody: _carregando
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.teal),
            )
          : _erro != null
              ? _erroView()
              : _buildDesktop(),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.teal),
            )
          : _erro != null
              ? _erroView()
              : _buildBody(),
    );
  }

  Widget _erroView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(_erro!,
                textAlign: TextAlign.center,
                style: tsJakarta(13, FontWeight.w400,
                    color: AppColors.muted)),
            const SizedBox(height: 14),
            TextButton(
                onPressed: _carregar,
                child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }

  // ── Desktop — saldo à esquerda, extrato à direita ────────────────────────

  String _subtituloDesktop() {
    final atualizado = _carteira?.atualizadoEm;
    if (atualizado == null) return 'Saldo e extrato da sua conta';
    return 'Última atualização: ${_formatarData(atualizado)}';
  }

  List<Transacao> get _extratoFiltrado {
    final todas = _carteira?.transacoes ?? const <Transacao>[];
    return switch (_filtroExtrato) {
      'entradas' =>
        todas.where((t) => t.tipo != TipoTransacao.saque).toList(),
      'saques' =>
        todas.where((t) => t.tipo == TipoTransacao.saque).toList(),
      _ => todas,
    };
  }

  Widget _buildDesktop() {
    final saldo = _carteira?.saldoAtual ?? 0.0;
    final ganhos = _carteira?.ganhosMensais ?? 0.0;
    final media = _carteira?.mediaPorTurno ?? 0.0;

    return ContentGrid(
      children: [
        GridCol(
          span: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WalletHero(
                balance:
                    'R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}',
                onWithdraw: _solicitarSaque,
                onExtract: _carregar,
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _statTile(Icons.trending_up_rounded,
                          'Ganhos mensais', 'R\$ ${ganhos.toStringAsFixed(0)}'),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _statTile(Icons.speed_rounded, 'Média/turno',
                          'R\$ ${media.toStringAsFixed(0)}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        GridCol(
          span: 8,
          child: PanelCard(
            title: 'Extrato',
            padding: const EdgeInsets.all(22),
            gap: 14,
            trailing: _buildFiltroExtrato(),
            child: _buildExtratoDesktop(),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroExtrato() {
    const opcoes = [
      ('todos', 'Tudo'),
      ('entradas', 'Entradas'),
      ('saques', 'Saques'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: opcoes.map((op) {
          final sel = _filtroExtrato == op.$1;
          return InkWell(
            onTap: () => setState(() => _filtroExtrato = op.$1),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? AppColors.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                op.$2,
                style: tsJakarta(11.5, FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExtratoDesktop() {
    final transacoes = _extratoFiltrado;
    if (transacoes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            _filtroExtrato == 'todos'
                ? 'Nenhuma transação registrada ainda.'
                : 'Nenhum lançamento neste filtro.',
            style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < transacoes.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          // Mesmo critério do extrato do celular, logo abaixo: o sinal vem do
          // tipo e não de "é saque ou não". O merge deixou os dois extratos
          // discordando — este ainda rotularia `reserva` e
          // `pagamento_enviado` como entrada.
          LedgerRow(
            title: transacoes[i].descricao,
            date: _formatarData(transacoes[i].criadoEm),
            amount: '${switch (transacoes[i].credito) {
              true => '+ ',
              false => '− ',
              null => '',
            }}R\$ ${transacoes[i].valor.toStringAsFixed(2).replaceAll('.', ',')}',
            isCredit: transacoes[i].credito,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    final saldo = _carteira?.saldoAtual ?? 0.0;
    final ganhos = _carteira?.ganhosMensais ?? 0.0;
    final media = _carteira?.mediaPorTurno ?? 0.0;
    final transacoes = _carteira?.transacoes ?? [];

    final saldoStr =
        'R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        WalletHero(
          balance: saldoStr,
          onWithdraw: _solicitarSaque,
          onExtract: _carregar,
        ),
        const SizedBox(height: 12),
        // Stats
        Row(
          children: [
            Expanded(
              child: _statTile(
                  Icons.trending_up_rounded,
                  'Ganhos mensais',
                  'R\$ ${ganhos.toStringAsFixed(0)}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile(
                  Icons.speed_rounded,
                  'Média/turno',
                  'R\$ ${media.toStringAsFixed(0)}'),
            ),
          ],
        ),
        SectionTitle(
          title: 'Histórico',
          action: 'Atualizar',
          onAction: _carregar,
        ),
        if (transacoes.isEmpty)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Center(
              child: Text(
                'Nenhuma transação registrada ainda.',
                style: tsJakarta(12.5, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ),
          )
        else
          LedgerCard(
            rows: transacoes
                .map((t) => LedgerRow(
                      title: t.descricao,
                      date: _formatarData(t.criadoEm),
                      // O sinal vem do tipo, não de "é saque ou não": reserva e
                      // pagamento enviado também saem da carteira. Tipo que o
                      // app não conhece vai sem sinal.
                      amount: '${switch (t.credito) {
                        true => '+ ',
                        false => '- ',
                        null => '',
                      }}R\$ ${t.valor.toStringAsFixed(2).replaceAll('.', ',')}',
                      isCredit: t.credito,
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _statTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.teal, size: 20),
          const SizedBox(height: 6),
          Text(label.toUpperCase(),
              style:
                  tsJakarta(8.5, FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(value,
              style:
                  tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        ],
      ),
    );
  }

  /// "Hoje, 14:30" / "Ontem, 09:15" / "12/08, 20:00".
  ///
  /// A data de referência vem de `widget.agora` — o mesmo mecanismo que as
  /// outras telas com golden já usam. Não leva parâmetro próprio como
  /// `serieUltimos7Dias` e `proximos()` porque aqui é método privado do
  /// State: quem chama já está dentro da tela, e um parâmetro que ninguém
  /// passa seria API morta.
  ///
  /// Sem isso, o dia em que alguém acrescentasse uma transação ao fixture
  /// seria o dia em que o golden da carteira passaria a virar sozinho à
  /// meia-noite.
  String _formatarData(DateTime d) {
    final agora = widget.agora ?? clock.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(d.year, d.month, d.day);
    final hora =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (dia == hoje) return 'Hoje, $hora';
    if (dia == hoje.subtract(const Duration(days: 1)))
      return 'Ontem, $hora';
    return '${d.day}/${d.month.toString().padLeft(2, '0')}, $hora';
  }
}
