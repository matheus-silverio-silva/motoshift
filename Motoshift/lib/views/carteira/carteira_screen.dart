import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/carteira.dart';
import '../../models/transacao.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/section_title.dart';
import '../../widgets/wallet_widgets.dart';

class CarteiraScreen extends StatefulWidget {
  const CarteiraScreen({super.key});

  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> {
  Carteira? _carteira;
  bool _carregando = false;
  String? _erro;

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
      final c = await api.buscarCarteira(id);
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
      await api.solicitarSaque(id, valor);
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
    return AppScaffold(
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
                      amount:
                          '${t.tipo == TipoTransacao.saque ? '-' : '+'} R\$ ${t.valor.toStringAsFixed(2).replaceAll('.', ',')}',
                      isCredit: t.tipo != TipoTransacao.saque,
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

  String _formatarData(DateTime d) {
    final agora = DateTime.now();
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
