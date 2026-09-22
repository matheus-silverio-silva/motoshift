import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/informe_anual.dart';
import '../../models/nota_fiscal.dart';
import '../../models/nota_fiscal_filtro.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../utils/exportar_csv.dart';
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

/// As duas abas da tela: as notas e o informe do ano.
enum _Aba { notas, informe }

class _NotasFiscaisScreenState extends State<NotasFiscaisScreen> {
  List<NotaFiscal> _notas = const [];
  List<NotaFiscalPendente> _pendentes = const [];
  bool _carregando = true;
  String? _erro;

  /// Turno sendo emitido agora — trava só o botão daquela linha.
  int? _emitindo;

  _Aba _aba = _Aba.notas;

  /// O filtro vai para o backend, e não para uma lista já baixada: a pessoa
  /// que tem dois anos de notas não deve baixar os dois para ver um mês.
  NotaFiscalFiltro _filtro = const NotaFiscalFiltro();

  /// Quantas notas existem no filtro atual — o header X-Total-Count.
  int _total = 0;

  /// Cresce com o "Carregar mais": a tela pede mais uma página do mesmo filtro.
  int _tamanho = 20;

  InformeAnual? _informe;
  int _anoInforme = DateTime.now().year;
  bool _carregandoInforme = false;
  bool _exportando = false;

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
      final pagina = await api.notasFiscais
          .listar(filtro: _filtro, pagina: 0, tamanho: _tamanho);
      // As pendências não dependem do filtro: são o que falta emitir, e some
      // da tela escondê-las porque o filtro pedia "canceladas".
      final pendentes = await api.notasFiscais.pendentes();
      if (!mounted) return;
      setState(() {
        _notas = pagina.notas;
        _total = pagina.total;
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

  Future<void> _aplicarFiltro(NotaFiscalFiltro novo) async {
    setState(() {
      _filtro = novo;
      _tamanho = 20;
      _carregando = true;
    });
    await _carregar();
  }

  Future<void> _carregarMais() async {
    setState(() => _tamanho += 20);
    await _carregar();
  }

  Future<void> _carregarInforme() async {
    setState(() => _carregandoInforme = true);
    try {
      final informe =
          await context.read<ApiService>().notasFiscais.resumo(ano: _anoInforme);
      if (mounted) setState(() => _informe = informe);
    } catch (_) {
      if (mounted) setState(() => _informe = null);
    } finally {
      if (mounted) setState(() => _carregandoInforme = false);
    }
  }

  Future<void> _exportarInforme() async {
    setState(() => _exportando = true);
    try {
      final csv = await context
          .read<ApiService>()
          .notasFiscais
          .exportarResumo(ano: _anoInforme);
      if (!mounted) return;
      await entregarCsv(context, csv, nomeSugerido: 'informe-$_anoInforme.csv');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
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

    if (_aba == _Aba.informe) return _corpoInforme(desktop: desktop);

    if (desktop) {
      return ContentGrid(
        children: [
          GridCol(span: 12, child: _barraDeAbas()),
          GridCol(span: 12, child: _barraDeFiltros()),
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
              subtitle: _resumoDoFiltro(),
              child: _notas.isEmpty
                  ? _buildVazio()
                  : Column(
                      children: [
                        for (final n in _notas) _buildNota(n),
                        if (_maisParaCarregar) _botaoCarregarMais(),
                      ],
                    ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _barraDeAbas(),
        const SizedBox(height: 12),
        _barraDeFiltros(),
        const SizedBox(height: 16),
        if (_pendentes.isNotEmpty) ...[
          _buildTituloSecao('A emitir', _pendentes.length),
          const SizedBox(height: 10),
          for (final p in _pendentes) _buildPendente(p),
          const SizedBox(height: 22),
        ],
        _buildTituloSecao('Notas emitidas', _total),
        const SizedBox(height: 4),
        Text(_resumoDoFiltro(),
            style: tsJakarta(11, FontWeight.w400, color: AppColors.muted)),
        const SizedBox(height: 10),
        if (_notas.isEmpty) _buildVazio() else ...[
          for (final n in _notas) _buildNota(n),
          if (_maisParaCarregar) _botaoCarregarMais(),
        ],
      ],
    );
  }

  bool get _maisParaCarregar => _notas.length < _total;

  /// O que o filtro está deixando de fora, em uma linha — senão uma lista
  /// vazia parece "não tenho notas" quando é só o filtro apertado.
  String _resumoDoFiltro() {
    if (_filtro.vazio) {
      return _total == 1 ? '1 nota no total' : '$_total notas no total';
    }
    final partes = <String>[
      if (_filtro.papel == 'prestador') 'como prestador',
      if (_filtro.papel == 'tomador') 'como tomador',
      if (_filtro.status == 'emitida') 'só as válidas',
      if (_filtro.status == 'cancelada') 'só as canceladas',
      if (_filtro.competenciaDe != null || _filtro.competenciaAte != null)
        'no período escolhido',
      if (_filtro.contraparteId != null) 'de uma contraparte',
    ];
    return '${_notas.length} de $_total — filtrando ${partes.join(', ')}';
  }

  Widget _botaoCarregarMais() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton(
        key: const Key('notas-carregar-mais'),
        onPressed: _carregarMais,
        child: Text('Carregar mais (${_total - _notas.length} restantes)',
            style: tsJakarta(12.5, FontWeight.w700, color: AppColors.teal)),
      ),
    );
  }

  // ── Abas e filtros ───────────────────────────────────────────────────────

  Widget _barraDeAbas() {
    return Row(
      children: [
        _abaBotao(_Aba.notas, 'Notas'),
        const SizedBox(width: 8),
        _abaBotao(_Aba.informe, 'Informe anual'),
      ],
    );
  }

  Widget _abaBotao(_Aba aba, String rotulo) {
    final sel = _aba == aba;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _aba = aba);
          if (aba == _Aba.informe && _informe == null) _carregarInforme();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppColors.teal : AppColors.surface2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(rotulo,
              style: tsJakarta(12.5, FontWeight.w700,
                  color: sel ? Colors.white : AppColors.muted)),
        ),
      ),
    );
  }

  /// Papel, situação, período de competência e contraparte. O filtro por
  /// turno existe na API e não aqui: quem procura a nota de um turno chega a
  /// ela pelo próprio turno.
  Widget _barraDeFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('Todas', _filtro.papel == null,
              () => _aplicarFiltro(_filtro.copyWith(limparPapel: true))),
          _chip('Prestei', _filtro.papel == 'prestador',
              () => _aplicarFiltro(_filtro.copyWith(papel: 'prestador'))),
          _chip('Tomei', _filtro.papel == 'tomador',
              () => _aplicarFiltro(_filtro.copyWith(papel: 'tomador'))),
          const SizedBox(width: 6),
          _chip('Válidas', _filtro.status == 'emitida',
              () => _aplicarFiltro(_filtro.status == 'emitida'
                  ? _filtro.copyWith(limparStatus: true)
                  : _filtro.copyWith(status: 'emitida'))),
          _chip('Canceladas', _filtro.status == 'cancelada',
              () => _aplicarFiltro(_filtro.status == 'cancelada'
                  ? _filtro.copyWith(limparStatus: true)
                  : _filtro.copyWith(status: 'cancelada'))),
          const SizedBox(width: 6),
          _chip(
            _rotuloDoPeriodo(),
            _filtro.competenciaDe != null || _filtro.competenciaAte != null,
            _escolherPeriodo,
            icone: Icons.calendar_today_rounded,
          ),
          if (_contrapartes().isNotEmpty) ...[
            const SizedBox(width: 6),
            _chipContraparte(),
          ],
        ],
      ),
    );
  }

  String _rotuloDoPeriodo() {
    final de = _filtro.competenciaDe;
    final ate = _filtro.competenciaAte;
    if (de == null && ate == null) return 'Competência';
    final f = DateFormat('dd/MM/yy', 'pt_BR');
    return '${de == null ? '…' : f.format(de)} – ${ate == null ? '…' : f.format(ate)}';
  }

  /// Tocar de novo no período limpa: é o mesmo gesto para ligar e desligar,
  /// como nas outras pílulas da barra.
  Future<void> _escolherPeriodo() async {
    if (_filtro.competenciaDe != null || _filtro.competenciaAte != null) {
      await _aplicarFiltro(_filtro.copyWith(limparPeriodo: true));
      return;
    }
    final hoje = DateTime.now();
    final faixa = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoje.year - 3),
      lastDate: DateTime(hoje.year + 1),
      locale: const Locale('pt', 'BR'),
      helpText: 'Competência (data do serviço)',
    );
    if (faixa == null) return;
    await _aplicarFiltro(
        _filtro.copyWith(competenciaDe: faixa.start, competenciaAte: faixa.end));
  }

  /// As contrapartes das notas à vista: a listagem não devolve "com quem eu
  /// tenho notas", então o menu é montado do que já veio.
  List<({int id, String nome})> _contrapartes() {
    final mapa = <int, String>{};
    for (final n in _notas) {
      if (n.souPrestador) {
        mapa[n.tomadorId] = n.tomadorNome;
      } else {
        mapa[n.prestadorId] = n.prestadorNome;
      }
    }
    return [for (final e in mapa.entries) (id: e.key, nome: e.value)];
  }

  Widget _chipContraparte() {
    final contrapartes = _contrapartes();
    final atual = _filtro.contraparteId;
    final nome =
        contrapartes.where((c) => c.id == atual).map((c) => c.nome).firstOrNull;

    return PopupMenuButton<int?>(
      key: const Key('notas-filtro-contraparte'),
      tooltip: 'Filtrar por contraparte',
      onSelected: (id) => _aplicarFiltro(id == null
          ? _filtro.copyWith(limparContraparte: true)
          : _filtro.copyWith(contraparteId: id)),
      itemBuilder: (_) => [
        const PopupMenuItem<int?>(value: null, child: Text('Todas as contrapartes')),
        for (final c in contrapartes)
          PopupMenuItem<int?>(value: c.id, child: Text(c.nome)),
      ],
      child: _corpoDoChip(nome ?? 'Contraparte', atual != null,
          icone: Icons.expand_more_rounded),
    );
  }

  Widget _chip(String rotulo, bool ativo, VoidCallback onTap, {IconData? icone}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: _corpoDoChip(rotulo, ativo, icone: icone),
      ),
    );
  }

  Widget _corpoDoChip(String rotulo, bool ativo, {IconData? icone}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ativo ? AppColors.tealSoft : AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ativo ? AppColors.teal : AppColors.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 14, color: ativo ? AppColors.tealDeep : AppColors.muted),
            const SizedBox(width: 5),
          ],
          Text(rotulo,
              style: tsJakarta(11.5, FontWeight.w700,
                  color: ativo ? AppColors.tealDeep : AppColors.muted)),
        ],
      ),
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

  // ── Informe anual ────────────────────────────────────────────────────────

  Widget _corpoInforme({required bool desktop}) {
    final inf = _informe;
    final blocos = <Widget>[
      _barraDeAbas(),
      const SizedBox(height: 12),
      _anosDoInforme(),
      const SizedBox(height: 14),
      if (_carregandoInforme)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
          ),
        )
      else if (inf == null)
        EmptyState(
          icon: Icons.summarize_outlined,
          titulo: 'Informe indisponível',
          subtitulo: 'Não foi possível calcular o informe de $_anoInforme.',
          acaoLabel: 'Tentar novamente',
          onAcao: _carregarInforme,
        )
      else ...[
        _totaisDoInforme(inf),
        const SizedBox(height: 12),
        _contrapartesDoInforme(inf),
        const SizedBox(height: 12),
        _mesesDoInforme(inf),
        const SizedBox(height: 12),
        _botaoExportarInforme(),
      ],
    ];

    if (desktop) {
      return ContentGrid(
        children: [for (final b in blocos) GridCol(span: 12, child: b)],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: blocos,
    );
  }

  /// O ano corrente e os dois anteriores. O app não sabe desde quando a conta
  /// existe, e três anos cobrem o que um informe costuma alcançar.
  Widget _anosDoInforme() {
    final atual = DateTime.now().year;
    return Row(
      key: const Key('informe-anos'),
      children: [
        for (final ano in [atual, atual - 1, atual - 2])
          _chip('$ano', _anoInforme == ano, () {
            if (_anoInforme == ano) return;
            setState(() => _anoInforme = ano);
            _carregarInforme();
          }),
      ],
    );
  }

  /// O total do ano vem do extrato, não das notas: é dinheiro que entrou,
  /// tenha virado documento ou não. Por isso o cartão diz, ao lado, quantos
  /// pagamentos ainda estão sem nota.
  Widget _totaisDoInforme(InformeAnual inf) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(inf.marca,
              style: tsJakarta(9, FontWeight.w800, color: Colors.white70)),
          const SizedBox(height: 8),
          Text('${inf.titulo} · ${inf.ano}',
              style: tsJakarta(11.5, FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(_moeda(inf.total),
              key: const Key('informe-total'),
              style: tsBricolage(28, FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            '${inf.pagamentos} pagamento(s) · ${inf.notasEmitidas} com nota'
            '${inf.semNota > 0 ? ' · ${inf.semNota} sem nota' : ''}',
            style: tsJakarta(11, FontWeight.w400, color: Colors.white70),
          ),
          if (inf.temRetencao) ...[
            const SizedBox(height: 6),
            Text(
              'Retido na fonte: ISS ${_moeda(inf.issRetido)} · '
              'IRRF ${_moeda(inf.irrfRetido)}',
              key: const Key('informe-retencao'),
              style: tsJakarta(11, FontWeight.w600, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contrapartesDoInforme(InformeAnual inf) {
    if (inf.contrapartes.isEmpty) {
      return EmptyState(
        icon: Icons.summarize_outlined,
        titulo: 'Nada em ${inf.ano}',
        subtitulo: inf.souPrestador
            ? 'Os turnos pagos a você aparecem aqui, mesmo antes de a nota ser gerada.'
            : 'Os turnos que você pagou aparecem aqui, por entregador.',
      );
    }
    return _cartaoDoInforme(
      inf.souPrestador ? 'Por fonte pagadora' : 'Por prestador',
      [
        for (final c in inf.contrapartes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(12.5, FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        '${c.documento ?? '${c.documentoTipo} não informado'} · '
                        '${c.pagamentos} pagamento(s) · ${c.notasEmitidas} com nota',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(10.5, FontWeight.w400,
                            color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(_moeda(c.total),
                    style: tsJakarta(12.5, FontWeight.w800,
                        color: AppColors.tealDeep)),
              ],
            ),
          ),
      ],
    );
  }

  /// Os doze meses, inclusive os zerados: a barra vazia de um mês é
  /// informação, e esconder o mês faria o ano parecer outro.
  Widget _mesesDoInforme(InformeAnual inf) {
    final maior = inf.meses.fold<double>(0, (m, x) => x.total > m ? x.total : m);
    return _cartaoDoInforme('Por mês', [
      for (final m in inf.meses)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(m.nome,
                    style: tsJakarta(10.5, FontWeight.w600,
                        color: AppColors.muted)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maior <= 0 ? 0 : m.total / maior,
                    minHeight: 8,
                    backgroundColor: AppColors.surface3,
                    valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: Text(_moeda(m.total),
                    textAlign: TextAlign.right,
                    style: tsJakarta(10.5, FontWeight.w600,
                        color: AppColors.text)),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _cartaoDoInforme(String titulo, List<Widget> filhos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 12),
          ...filhos,
        ],
      ),
    );
  }

  Widget _botaoExportarInforme() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('informe-exportar'),
        onPressed: _exportando ? null : _exportarInforme,
        icon: _exportando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.teal))
            : const Icon(Icons.download_rounded, size: 18, color: AppColors.tealDeep),
        label: Text('Exportar CSV',
            style: tsJakarta(12.5, FontWeight.w700, color: AppColors.tealDeep)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: AppColors.teal, width: 1.5),
        ),
      ),
    );
  }

  String _moeda(double valor) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
}
