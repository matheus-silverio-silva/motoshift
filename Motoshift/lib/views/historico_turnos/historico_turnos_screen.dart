import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';

class HistoricoTurnosScreen extends StatefulWidget {
  const HistoricoTurnosScreen({super.key});

  @override
  State<HistoricoTurnosScreen> createState() =>
      _HistoricoTurnosScreenState();
}

class _HistoricoTurnosScreenState extends State<HistoricoTurnosScreen> {
  List<Turno> _turnos = const [];
  bool _carregando = true;
  String _filtro = 'todos'; // todos | finalizados | cancelados

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

    try {
      final List<Turno> lista;
      if (auth.usuario?.tipo == TipoUsuario.lojista) {
        lista = await api.listarTurnosLojista(id);
      } else {
        lista = await api.listarMeusTurnos(id);
      }
      if (mounted) {
        setState(() {
          _turnos = lista
              .where((t) =>
                  t.status == StatusTurno.finalizado ||
                  t.status == StatusTurno.cancelado)
              .toList()
            ..sort((a, b) => b.dataInicio.compareTo(a.dataInicio));
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<Turno> get _filtrados {
    if (_filtro == 'finalizados') {
      return _turnos
          .where((t) => t.status == StatusTurno.finalizado)
          .toList();
    }
    if (_filtro == 'cancelados') {
      return _turnos
          .where((t) => t.status == StatusTurno.cancelado)
          .toList();
    }
    return _turnos;
  }

  double get _totalGanho => _turnos
      .where((t) => t.status == StatusTurno.finalizado)
      .fold(0.0, (acc, t) => acc + t.valorEstimado);

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      header: AppHeader.back(title: 'Histórico de turnos'),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : _turnos.isEmpty
              ? _buildVazio()
              : _buildLista(),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.tealSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_rounded,
                  color: AppColors.teal, size: 32),
            ),
            const SizedBox(height: 14),
            Text('Sem histórico ainda',
                style: tsBricolage(16, FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              'Turnos concluídos ou cancelados aparecem aqui.',
              textAlign: TextAlign.center,
              style: tsJakarta(12, FontWeight.w400,
                  color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista() {
    final tipo = context.read<AuthService>().usuario?.tipo;
    final isLojista = tipo == TipoUsuario.lojista;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _buildResumo(isLojista),
        const SizedBox(height: 12),
        _buildFiltros(),
        const SizedBox(height: 12),
        if (_filtrados.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: Center(
              child: Text(
                'Nenhum turno nesse filtro.',
                style: tsJakarta(12, FontWeight.w400,
                    color: AppColors.muted),
              ),
            ),
          )
        else
          ..._filtrados.map((t) => _buildTurnoCard(t, isLojista)),
      ],
    );
  }

  Widget _buildResumo(bool isLojista) {
    final concluidos =
        _turnos.where((t) => t.status == StatusTurno.finalizado).length;
    final cancelados =
        _turnos.where((t) => t.status == StatusTurno.cancelado).length;

    return Row(
      children: [
        Expanded(
          child: _statCell(
            label: 'CONCLUÍDOS',
            value: '$concluidos',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCell(
            label: 'CANCELADOS',
            value: '$cancelados',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCell(
            label: isLojista ? 'GASTO TOTAL' : 'GANHO TOTAL',
            value: 'R\$ ${_totalGanho.toStringAsFixed(0)}',
            highlight: true,
          ),
        ),
      ],
    );
  }

  Widget _statCell({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.tealSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight ? AppColors.tealDeep : AppColors.line,
            width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: tsJakarta(8.5, FontWeight.w700,
                  color: highlight
                      ? AppColors.tealDeep
                      : AppColors.muted)),
          const SizedBox(height: 3),
          Text(value,
              style: tsBricolage(15, FontWeight.w800,
                  color: highlight
                      ? AppColors.tealDeep
                      : AppColors.ink)),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    const opcoes = [
      ('todos', 'Todos'),
      ('finalizados', 'Finalizados'),
      ('cancelados', 'Cancelados'),
    ];

    return Row(
      children: opcoes.map((op) {
        final sel = _filtro == op.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _filtro = op.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? AppColors.teal : AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                op.$2,
                style: tsJakarta(12, FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTurnoCard(Turno t, bool isLojista) {
    final dataFmt =
        DateFormat('dd/MM/yyyy', 'pt_BR').format(t.dataInicio);

    return ShiftCard(
      name: t.titulo,
      meta: [dataFmt, t.regiao],
      value: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
      iconData: isLojista
          ? Icons.store_outlined
          : Icons.two_wheeler_outlined,
      pillLabel: t.status.label,
      pillVariant: t.status == StatusTurno.finalizado
          ? PillVariant.good
          : PillVariant.ghost,
      onTap: () => Navigator.pushNamed(
        context,
        isLojista ? AppRoutes.turnoLojista : AppRoutes.detalheTurno,
        arguments: t,
      ),
    );
  }
}
