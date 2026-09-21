import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/extrato_filtro.dart';
import '../../models/transacao.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import 'extrato_filtros.dart';
import 'lancamento_tile.dart';

/// Extrato unificado dos dois perfis.
///
/// Serve lojista e entregador com a mesma tela porque a pergunta é a mesma — o
/// que entrou, o que saiu, quando e com quem —, e o sinal de cada linha vem da
/// `natureza` gravada no lançamento, não de um `switch` sobre o tipo que esta
/// versão do app conhece.
///
/// O filtro vai para a API. Antes a tela baixava o extrato inteiro e escondia
/// linhas; com isso não dava para paginar, e a resposta crescia sem limite.
class ExtratoScreen extends StatefulWidget {
  const ExtratoScreen({super.key, this.filtroInicial, this.agora});

  /// Pré-filtro, quando a tela é aberta a partir de um turno.
  final ExtratoFiltro? filtroInicial;

  /// Fixa o "agora" — só os testes passam isto, como nas outras telas com
  /// golden.
  final DateTime? agora;

  @override
  State<ExtratoScreen> createState() => _ExtratoScreenState();
}

class _ExtratoScreenState extends State<ExtratoScreen> {
  static const int _tamanhoDaPagina = 20;

  final ScrollController _scroll = ScrollController();
  final List<Transacao> _lancamentos = [];

  late ExtratoFiltro _filtro;
  int _pagina = 0;
  int _total = 0;
  bool _carregando = false;
  bool _exportando = false;
  String? _erro;

  DateTime get _hoje => widget.agora ?? clock.now();

  bool get _temMais => _lancamentos.length < _total;

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial ?? const ExtratoFiltro();
    _scroll.addListener(_aoRolar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recarregar());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Carrega a próxima página quando faltam ~400px para o fim da lista.
  void _aoRolar() {
    if (_carregando || !_temMais) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _carregarPagina();
    }
  }

  Future<void> _recarregar() async {
    setState(() {
      _lancamentos.clear();
      _pagina = 0;
      _total = 0;
      _erro = null;
    });
    await _carregarPagina();
  }

  Future<void> _carregarPagina() async {
    if (_carregando) return;
    setState(() => _carregando = true);
    try {
      final resposta = await context.read<ApiService>().carteira.buscarExtrato(
            filtro: _filtro,
            pagina: _pagina,
            tamanho: _tamanhoDaPagina,
          );
      if (!mounted) return;
      setState(() {
        _lancamentos.addAll(resposta.itens);
        _total = resposta.total;
        _pagina++;
        _erro = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Erro ao carregar o extrato.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirFiltros() async {
    final novo = await showModalBottomSheet<ExtratoFiltro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExtratoFiltros(inicial: _filtro, hoje: _hoje),
    );
    if (novo != null) {
      setState(() => _filtro = novo);
      _recarregar();
    }
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final csv = await context
          .read<ApiService>()
          .carteira
          .exportarExtratoCsv(filtro: _filtro);
      if (!mounted) return;
      final linhas = csv.isEmpty ? 0 : csv.trim().split('\n').length - 1;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$linhas lançamento(s) exportados.'),
        backgroundColor: AppColors.good,
      ));
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

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Extrato'),
      desktopTitle: 'Extrato',
      desktopSubtitle: 'Todos os lançamentos da sua carteira',
      desktopBody: _conteudo(desktop: true),
      body: _conteudo(desktop: false),
    );
  }

  Widget _conteudo({required bool desktop}) {
    return Column(
      children: [
        _barraDeFiltros(),
        if (_erro != null) _caixaDeErro(_erro!),
        Expanded(child: _lista(desktop: desktop)),
      ],
    );
  }

  Widget _barraDeFiltros() {
    final ativos = _filtro.quantidadeAtiva;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('extrato-abrir-filtros'),
              onPressed: _abrirFiltros,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(ativos == 0 ? 'Filtrar' : 'Filtros ($ativos)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor:
                    ativos == 0 ? AppColors.text : AppColors.teal,
              ),
            ),
          ),
          if (ativos > 0) ...[
            const SizedBox(width: 8),
            IconButton(
              key: const Key('extrato-limpar-filtros'),
              tooltip: 'Limpar filtros',
              icon: const Icon(Icons.filter_alt_off_outlined),
              onPressed: () {
                setState(() => _filtro = const ExtratoFiltro());
                _recarregar();
              },
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            key: const Key('extrato-exportar'),
            tooltip: 'Exportar CSV',
            icon: _exportando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            onPressed: _exportando ? null : _exportar,
          ),
        ],
      ),
    );
  }

  Widget _lista({required bool desktop}) {
    if (_lancamentos.isEmpty && _carregando) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
      );
    }
    if (_lancamentos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _filtro.vazio
                ? 'Nenhum lançamento na sua carteira ainda.'
                : 'Nenhum lançamento com esses filtros.',
            key: const Key('extrato-vazio'),
            textAlign: TextAlign.center,
            style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
          ),
        ),
      );
    }

    // Agrupamento por dia: a data vira cabeçalho em vez de se repetir em cada
    // linha, que é como um extrato bancário é lido.
    final grupos = _agruparPorDia();

    return RefreshIndicator(
      onRefresh: _recarregar,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(desktop ? 0 : 16, 0, desktop ? 0 : 16, 24),
        itemCount: grupos.length + 1,
        itemBuilder: (context, i) {
          if (i == grupos.length) return _rodape();
          final grupo = grupos[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text(grupo.rotulo,
                    style: tsJakarta(11.5, FontWeight.w700,
                        color: AppColors.muted)),
              ),
              for (final t in grupo.lancamentos)
                LancamentoTile(
                  lancamento: t,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.lancamento,
                    arguments: t,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _rodape() {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_temMais) return const SizedBox(height: 40);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text('$_total lançamento(s)',
            key: const Key('extrato-total'),
            style: tsJakarta(11.5, FontWeight.w500, color: AppColors.muted)),
      ),
    );
  }

  Widget _caixaDeErro(String mensagem) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 17, color: AppColors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(mensagem,
                style: tsJakarta(12, FontWeight.w500, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  List<_GrupoDoDia> _agruparPorDia() {
    final grupos = <_GrupoDoDia>[];
    for (final t in _lancamentos) {
      final dia = DateTime(t.criadoEm.year, t.criadoEm.month, t.criadoEm.day);
      if (grupos.isEmpty || grupos.last.dia != dia) {
        grupos.add(_GrupoDoDia(dia, _rotuloDoDia(dia), []));
      }
      grupos.last.lancamentos.add(t);
    }
    return grupos;
  }

  String _rotuloDoDia(DateTime dia) {
    final hoje = DateTime(_hoje.year, _hoje.month, _hoje.day);
    final diferenca = hoje.difference(dia).inDays;
    if (diferenca == 0) return 'Hoje';
    if (diferenca == 1) return 'Ontem';
    return '${dia.day.toString().padLeft(2, '0')}/'
        '${dia.month.toString().padLeft(2, '0')}/${dia.year}';
  }
}

class _GrupoDoDia {
  _GrupoDoDia(this.dia, this.rotulo, this.lancamentos);

  final DateTime dia;
  final String rotulo;
  final List<Transacao> lancamentos;
}
