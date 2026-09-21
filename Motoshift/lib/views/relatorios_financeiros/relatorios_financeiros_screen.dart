import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/extrato_filtro.dart';
import '../../models/resumo_financeiro.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';

/// Relatórios financeiros: resumo do período, fluxo de caixa e exportação.
///
/// Os números vêm somados do backend — o app não percorre lançamentos para
/// montar total nenhum. Isso não é detalhe de implementação: enquanto a conta
/// era feita aqui, ela dependia de o cliente ter baixado o extrato inteiro, e
/// só funcionava enquanto o extrato fosse pequeno.
class RelatoriosFinanceirosScreen extends StatefulWidget {
  const RelatoriosFinanceirosScreen({super.key, this.agora});

  /// Fixa o "agora" — só os testes passam isto.
  final DateTime? agora;

  @override
  State<RelatoriosFinanceirosScreen> createState() =>
      _RelatoriosFinanceirosScreenState();
}

class _RelatoriosFinanceirosScreenState
    extends State<RelatoriosFinanceirosScreen> {
  AtalhoDePeriodo _periodo = AtalhoDePeriodo.trintaDias;
  String _agrupamento = 'dia';

  ResumoFinanceiro? _resumo;
  List<PontoDeFluxo> _fluxo = const [];
  bool _carregando = true;
  bool _exportando = false;
  String? _erro;

  DateTime get _hoje => widget.agora ?? clock.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final (de, ate) = _periodo.intervalo(_hoje);
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final api = context.read<ApiService>().carteira;
      // As duas chamadas em paralelo: são independentes, e encadeá-las
      // dobraria o tempo de abertura da tela sem necessidade.
      final resultados = await Future.wait([
        api.buscarResumo(dataInicio: de, dataFim: ate),
        api.buscarFluxo(agrupamento: _agrupamento, dataInicio: de, dataFim: ate),
      ]);
      if (!mounted) return;
      setState(() {
        _resumo = resultados[0] as ResumoFinanceiro;
        _fluxo = resultados[1] as List<PontoDeFluxo>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Erro ao carregar o relatório.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _exportar() async {
    final (de, ate) = _periodo.intervalo(_hoje);
    setState(() => _exportando = true);
    try {
      final csv = await context.read<ApiService>().carteira.exportarExtratoCsv(
            filtro: ExtratoFiltro(dataInicio: de, dataFim: ate),
          );
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
      header: AppHeader.back(title: 'Relatórios'),
      desktopTitle: 'Relatórios',
      desktopSubtitle: 'Resumo do período, fluxo de caixa e exportação',
      rotaDaSecao: AppRoutes.relatorioFinanceiro,
      desktopBody: _desktop(),
      body: _mobile(),
    );
  }

  Widget _mobile() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _seletorDePeriodo(),
          const SizedBox(height: 16),
          if (_erro != null) _caixaDeErro(_erro!) else ...[
            _cartoesDeResumo(),
            const SizedBox(height: 16),
            _painelDeFluxo(),
            const SizedBox(height: 16),
            _painelPorTipo(),
            const SizedBox(height: 16),
            _botaoExportar(),
          ],
        ],
      ),
    );
  }

  Widget _desktop() {
    if (_erro != null) return _caixaDeErro(_erro!);
    return ContentGrid(
      children: [
        GridCol(
          span: 12,
          child: Row(
            children: [
              Expanded(child: _seletorDePeriodo()),
              const SizedBox(width: 12),
              _botaoExportar(),
            ],
          ),
        ),
        GridCol(span: 12, child: _cartoesDeResumo()),
        GridCol(span: 7, child: _painelDeFluxo()),
        GridCol(span: 5, child: _painelPorTipo()),
      ],
    );
  }

  Widget _seletorDePeriodo() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in AtalhoDePeriodo.values)
          ChoiceChip(
            key: Key('relatorio-periodo-${a.name}'),
            label: Text(a.label),
            selected: _periodo == a,
            onSelected: (_) {
              setState(() => _periodo = a);
              _carregar();
            },
          ),
      ],
    );
  }

  Widget _cartoesDeResumo() {
    final r = _resumo;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _cartao('Entradas', r?.entradas, AppColors.good,
                    const Key('relatorio-entradas'))),
            const SizedBox(width: 10),
            Expanded(
                child: _cartao('Saídas', r?.saidas, AppColors.error,
                    const Key('relatorio-saidas'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _cartao('Líquido', r?.liquido, AppColors.ink,
                    const Key('relatorio-liquido'))),
            const SizedBox(width: 10),
            Expanded(
                child: _cartao('Disponível', r?.disponivel, AppColors.teal,
                    const Key('relatorio-disponivel'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Os dois números que só fazem sentido para um dos perfis: vêm
            // zerados para quem não tem aquele tipo de pendência, e o rótulo
            // diz de quem é cada um.
            Expanded(
                child: _cartao('A receber', r?.aReceber, AppColors.muted,
                    const Key('relatorio-a-receber'))),
            const SizedBox(width: 10),
            Expanded(
                child: _cartao('Comprometido', r?.comprometido, AppColors.muted,
                    const Key('relatorio-comprometido'))),
          ],
        ),
      ],
    );
  }

  Widget _cartao(String rotulo, double? valor, Color cor, Key key) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo,
              style: tsJakarta(11, FontWeight.w600, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(valor == null ? '—' : _moeda(valor),
              style: tsBricolage(17, FontWeight.w800, color: cor)),
        ],
      ),
    );
  }

  Widget _painelDeFluxo() {
    return PanelCard(
      title: 'Fluxo de caixa',
      subtitle: 'Entradas e saídas do período',
      padding: const EdgeInsets.all(16),
      gap: 12,
      trailing: DropdownButton<String>(
        key: const Key('relatorio-agrupamento'),
        value: _agrupamento,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'dia', child: Text('Dia')),
          DropdownMenuItem(value: 'semana', child: Text('Semana')),
          DropdownMenuItem(value: 'mes', child: Text('Mês')),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _agrupamento = v);
          _carregar();
        },
      ),
      child: _carregando
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.teal)),
            )
          : _grafico(),
    );
  }

  /// Barras de entrada e saída lado a lado, desenhadas à mão.
  ///
  /// Sem biblioteca de gráfico: são duas barras por período, e uma dependência
  /// a mais no projeto para isso custaria mais do que resolve.
  Widget _grafico() {
    if (_fluxo.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('Sem lançamentos no período.',
              style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted)),
        ),
      );
    }

    final maximo = _fluxo
        .map((p) => p.entradas > p.saidas ? p.entradas : p.saidas)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _fluxo.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = _fluxo[i];
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _barra(p.entradas, maximo, AppColors.good),
                    const SizedBox(width: 4),
                    _barra(p.saidas, maximo, AppColors.error),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 56,
                child: Text(p.rotulo,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(9.5, FontWeight.w500,
                        color: AppColors.muted)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _barra(double valor, double maximo, Color cor) {
    // Altura mínima de 2px: um período com movimento pequeno some se a barra
    // for estritamente proporcional, e "quase zero" não é "nada".
    final altura = maximo <= 0 ? 2.0 : (valor / maximo * 140).clamp(2.0, 140.0);
    return Tooltip(
      message: _moeda(valor),
      child: Container(
        width: 20,
        height: altura,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: valor <= 0 ? 0.25 : 1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
    );
  }

  Widget _painelPorTipo() {
    final itens = _resumo?.porTipo ?? const <TotalPorTipo>[];
    return PanelCard(
      title: 'Por tipo de lançamento',
      subtitle: 'Onde o dinheiro se moveu no período',
      padding: const EdgeInsets.all(16),
      gap: 12,
      child: itens.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Sem lançamentos no período.',
                    style:
                        tsJakarta(12.5, FontWeight.w400, color: AppColors.muted)),
              ),
            )
          : Column(
              children: [
                for (final i in itens)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            // A cor vem da natureza que o backend mandou — a
                            // tela não decide de que lado o dinheiro anda.
                            color: i.natureza?.isCredito ?? true
                                ? AppColors.good
                                : AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(i.tipo.label,
                              style: tsJakarta(12.5, FontWeight.w600,
                                  color: AppColors.text)),
                        ),
                        Text('${i.quantidade}x',
                            style: tsJakarta(11, FontWeight.w400,
                                color: AppColors.muted)),
                        const SizedBox(width: 10),
                        Text(_moeda(i.total),
                            style: tsBricolage(13, FontWeight.w800,
                                color: AppColors.ink)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _botaoExportar() {
    return OutlinedButton.icon(
      key: const Key('relatorio-exportar'),
      onPressed: _exportando ? null : _exportar,
      icon: _exportando
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.download_rounded, size: 18),
      label: const Text('Exportar CSV'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }

  Widget _caixaDeErro(String mensagem) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensagem,
                style: tsJakarta(12.5, FontWeight.w500, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}
