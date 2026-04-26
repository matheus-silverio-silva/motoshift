import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/historico_item_entity.dart';
import '../../presentation/providers/historico_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

// ============================================================
// PRESENTATION — Histórico de Serviços (RF04)
// Abas: Todos / Entregas / Turnos — consome HistoricoProvider.
// ============================================================

class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  static const _filtros = [null, TipoServico.pedido, TipoServico.turno];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  void _carregar({TipoServico? tipo}) {
    final id = context.read<AuthService>().usuario?.id;
    if (id == null) return;
    context.read<HistoricoProvider>().setFiltro(tipo, id);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.onSurface,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Histórico',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          onTap: (i) => _carregar(tipo: _filtros[i]),
          labelStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          tabs: const [
            Tab(text: 'Todos'),
            Tab(text: 'Entregas'),
            Tab(text: 'Turnos'),
          ],
        ),
      ),
      body: Consumer<HistoricoProvider>(
        builder: (context, provider, _) {
          if (provider.carregando && provider.itens.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (provider.erro != null && provider.itens.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: AppColors.onSurfaceVariant, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      provider.erro!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _carregar,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.itens.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded,
                      color: AppColors.onSurfaceVariant, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum registro encontrado',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            itemCount: provider.itens.length,
            itemBuilder: (_, i) => _buildItem(provider.itens[i]),
          );
        },
      ),
    );
  }

  Widget _buildItem(HistoricoItemEntity item) {
    final cor = _corStatus(item.status);
    final positivo = item.status == StatusHistorico.concluido;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Ícone
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.tipoServico == TipoServico.pedido
                  ? Icons.delivery_dining_rounded
                  : Icons.work_outline_rounded,
              color: cor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.titulo,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd/MM/yy • HH:mm').format(item.data),
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.status.label,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Valor
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                positivo
                    ? '+ ${_currency.format(item.valor)}'
                    : _currency.format(item.valor),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: positivo ? Colors.green.shade700 : AppColors.onSurface,
                ),
              ),
              Text(
                item.tipoServico.label,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _corStatus(StatusHistorico s) => switch (s) {
        StatusHistorico.concluido => Colors.green.shade600,
        StatusHistorico.cancelado => Colors.red.shade600,
        StatusHistorico.emAndamento => AppColors.primary,
      };
}
