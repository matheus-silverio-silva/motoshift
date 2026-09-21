import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/nota_fiscal.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/empty_state.dart';
import 'nota_fiscal_detalhe.dart';

/// Estado inicial pedido à tela de notas fiscais.
class NotasFiscaisArgs {
  const NotasFiscaisArgs({this.notaId});

  /// Nota a abrir ao chegar — vem da notificação de nota emitida.
  final int? notaId;
}

/// Notas fiscais de serviço — a mesma tela para os dois papéis.
///
/// O entregador presta o serviço e o lojista o toma, então o documento é um
/// só; o que muda é o lado em que cada um aparece nele. Ambos podem emitir, e
/// é o backend que diz, em cada nota, qual é o papel de quem está olhando.
class NotasFiscaisScreen extends StatefulWidget {
  const NotasFiscaisScreen({super.key});

  @override
  State<NotasFiscaisScreen> createState() => _NotasFiscaisScreenState();
}

class _NotasFiscaisScreenState extends State<NotasFiscaisScreen> {
  List<NotaFiscal> _notas = const [];
  List<NotaFiscalPendente> _pendentes = const [];
  bool _carregando = true;
  String? _erro;

  /// Turno sendo emitido agora — trava só o botão daquela linha.
  int? _emitindo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _carregar();
      if (!mounted) return;
      // Veio de uma notificação de nota fiscal: abre aquela nota, em vez de
      // deixar o usuário procurá-la numa lista que pode ter dezenas.
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is NotasFiscaisArgs && args.notaId != null) {
        final nota = _notas.where((n) => n.id == args.notaId).firstOrNull;
        if (nota != null) _abrirDetalhe(nota);
      }
    });
  }

  Future<void> _carregar() async {
    final api = context.read<ApiService>();
    try {
      final notas = await api.notasFiscais.listar();
      final pendentes = await api.notasFiscais.pendentes();
      if (!mounted) return;
      setState(() {
        _notas = notas;
        _pendentes = pendentes;
        _erro = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar suas notas fiscais.';
        _carregando = false;
      });
    }
  }

  Future<void> _emitir(NotaFiscalPendente pendente) async {
    setState(() => _emitindo = pendente.turnoId);
    try {
      final nota = await context.read<ApiService>().notasFiscais.emitir(
            pendente.turnoId,
            prestadorId: pendente.prestadorId,
          );
      if (!mounted) return;
      setState(() => _emitindo = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('NFS-e nº ${nota.numeroFormatado} emitida.'),
          backgroundColor: AppColors.good,
        ),
      );
      await _carregar();
      if (mounted) _abrirDetalhe(nota);
    } catch (e) {
      if (!mounted) return;
      setState(() => _emitindo = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _abrirDetalhe(NotaFiscal nota) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotaFiscalDetalhe(
        nota: nota,
        onCancelada: (cancelada) {
          setState(() {
            _notas = [
              for (final n in _notas) if (n.id == cancelada.id) cancelada else n,
            ];
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Notas fiscais'),
      desktopTitle: 'Notas fiscais',
      desktopSubtitle: _carregando ? 'Carregando…' : _subtitulo(),
      rotaDaSecao: AppRoutes.notasFiscais,
      desktopBody: _buildCorpo(desktop: true),
      body: _buildCorpo(desktop: false),
    );
  }

  String _subtitulo() {
    final emitidas = _notas.where((n) => !n.cancelada).length;
    final partes = <String>[
      if (_pendentes.isNotEmpty)
        _pendentes.length == 1
            ? '1 turno a emitir'
            : '${_pendentes.length} turnos a emitir',
      emitidas == 1 ? '1 nota emitida' : '$emitidas notas emitidas',
    ];
    final texto = partes.join(' · ');
    return texto[0].toUpperCase() + texto.substring(1);
  }

  Widget _buildCorpo({required bool desktop}) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            titulo: 'Não foi possível carregar',
            subtitulo: _erro,
            acaoLabel: 'Tentar novamente',
            onAcao: () {
              setState(() {
                _carregando = true;
                _erro = null;
              });
              _carregar();
            },
          ),
        ),
      );
    }

    if (desktop) {
      return ContentGrid(
        children: [
          if (_pendentes.isNotEmpty)
            GridCol(
              span: 12,
              child: PanelCard(
                title: 'A emitir',
                subtitle: 'Turnos concluídos que ainda não têm nota fiscal',
                child: Column(
                  children: [for (final p in _pendentes) _buildPendente(p)],
                ),
              ),
            ),
          GridCol(
            span: 12,
            child: PanelCard(
              title: 'Notas emitidas',
              child: _notas.isEmpty
                  ? _buildVazio()
                  : Column(
                      children: [for (final n in _notas) _buildNota(n)],
                    ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_pendentes.isNotEmpty) ...[
          _buildTituloSecao('A emitir', _pendentes.length),
          const SizedBox(height: 10),
          for (final p in _pendentes) _buildPendente(p),
          const SizedBox(height: 22),
        ],
        _buildTituloSecao('Notas emitidas', _notas.length),
        const SizedBox(height: 10),
        if (_notas.isEmpty) _buildVazio() else
          for (final n in _notas) _buildNota(n),
      ],
    );
  }

  Widget _buildVazio() {
    return const EmptyState(
      icon: Icons.receipt_long_outlined,
      titulo: 'Nenhuma nota fiscal ainda',
      subtitulo:
          'A nota de cada turno pode ser emitida assim que ele é finalizado. '
          'Entregador e lojista veem o mesmo documento.',
    );
  }

  Widget _buildTituloSecao(String titulo, int quantidade) {
    return Row(
      children: [
        Text(titulo,
            style: tsBricolage(15, FontWeight.w800, color: AppColors.ink)),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$quantidade',
              style:
                  tsJakarta(10.5, FontWeight.w800, color: AppColors.muted)),
        ),
      ],
    );
  }

  // ── Linhas ───────────────────────────────────────────────────────────────

  Widget _buildPendente(NotaFiscalPendente p) {
    final data = DateFormat('dd/MM/yyyy', 'pt_BR').format(p.dataInicio);
    final emitindo = _emitindo == p.turnoId;
    final rotuloLado = p.papel == 'prestador'
        ? 'Tomador: ${p.contraparteNome}'
        : 'Prestador: ${p.contraparteNome}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.tituloTurno,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(12.5, FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('$data · $rotuloLado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(_moeda(p.valorServico),
                    style: tsJakarta(12, FontWeight.w800,
                        color: AppColors.tealDeep)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: emitindo ? null : () => _emitir(p),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.onTertiary,
              disabledBackgroundColor: AppColors.surface3,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: emitindo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.muted),
                  )
                : Text('Emitir',
                    style: tsJakarta(12.5, FontWeight.w700,
                        color: AppColors.onTertiary)),
          ),
        ],
      ),
    );
  }

  Widget _buildNota(NotaFiscal n) {
    final emitida = DateFormat('dd/MM/yyyy', 'pt_BR').format(n.emitidaEm);
    final contraparte =
        n.souPrestador ? 'Tomador: ${n.tomadorNome}' : 'Prestador: ${n.prestadorNome}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _abrirDetalhe(n),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: n.cancelada
                        ? AppColors.surface3
                        : AppColors.tealSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    n.cancelada
                        ? Icons.receipt_long_outlined
                        : Icons.receipt_long_rounded,
                    size: 20,
                    color:
                        n.cancelada ? AppColors.muted : AppColors.tealDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text('NFS-e ${n.numeroFormatado}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tsJakarta(12.5, FontWeight.w700,
                                    color: AppColors.ink)),
                          ),
                          if (n.cancelada) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Cancelada',
                                  style: tsJakarta(9.5, FontWeight.w800,
                                      color: AppColors.error)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('$emitida · $contraparte',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(10.5, FontWeight.w400,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_moeda(n.valorLiquido),
                        style: tsJakarta(12.5, FontWeight.w800,
                            color: n.cancelada
                                ? AppColors.muted
                                : AppColors.tealDeep)),
                    const SizedBox(height: 2),
                    Text('líquido',
                        style: tsJakarta(9.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _moeda(double valor) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
}
