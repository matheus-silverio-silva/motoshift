import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/extrato_filtro.dart';
import '../../models/resumo_financeiro.dart';
import '../../models/transacao.dart';
import '../../models/usuario.dart';
import '../../models/dre.dart';
import '../../routes/app_routes.dart';
import '../../routes/nav_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/relatorio_pdf.dart';
import '../../theme/app_theme.dart';
import '../../utils/exportar_csv.dart';
import '../../utils/exportar_pdf.dart';
import '../../widgets/escolher_exportacao.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/seletor_de_periodo.dart';

/// Relatórios financeiros: resumo do período, fluxo de caixa e exportação.
///
/// Os números vêm somados do backend — o app não percorre lançamentos para
/// montar total nenhum. Isso não é detalhe de implementação: enquanto a conta
/// era feita aqui, ela dependia de o cliente ter baixado o extrato inteiro, e
/// só funcionava enquanto o extrato fosse pequeno.
///
/// Cada papel vê os seus números e só eles. O entregador presta serviço:
/// recebido, retido na fonte, sacado, disponível e a receber. O lojista
/// contrata: recarregado, pago a entregadores, devolvido, disponível e
/// comprometido. "Entradas" e "Saídas" saíram dos cartões porque diziam coisas
/// diferentes para cada um — a entrada do lojista é recarga, não receita, e a
/// saída do entregador é saque, não custo.
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

  TipoUsuario get _papel =>
      context.read<AuthService>().usuario?.tipo ?? TipoUsuario.motoboy;

  bool get _souLojista => _papel == TipoUsuario.lojista;

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

  /// Planilha: o extrato do período em CSV, como sempre foi. PDF: o que a
  /// tela mostra — os cartões do papel, a quebra por tipo e o fluxo — mais os
  /// lançamentos do período.
  Future<void> _exportar() async {
    final formato = await escolherFormatoExportacao(context);
    if (formato == null || !mounted) return;
    final (de, ate) = _periodo.intervalo(_hoje);
    final filtro = ExtratoFiltro(dataInicio: de, dataFim: ate);
    setState(() => _exportando = true);
    try {
      final carteira = context.read<ApiService>().carteira;
      if (formato == FormatoExportacao.planilha) {
        final csv = await carteira.exportarExtratoCsv(filtro: filtro);
        if (!mounted) return;
        await entregarCsv(context, csv, nomeSugerido: 'relatorio.csv');
        return;
      }
      // Os números do PDF são os da tela: o resumo e o fluxo já carregados
      // para este período, e não uma segunda consulta que poderia discordar.
      final resumo = _resumo ?? await carteira.buscarResumo(dataInicio: de, dataFim: ate);
      final lancamentos = await carteira.exportarExtratoLista(filtro: filtro);
      if (!mounted) return;
      final dre = await _dreParaOPdf(de, ate);
      if (!mounted) return;
      final usuario = context.read<AuthService>().usuario;
      final bytes = await RelatorioPdf.relatorio(
        titular: TitularDoPdf(nome: usuario?.nome ?? '', papel: _papel),
        de: de,
        ate: ate,
        resumo: resumo,
        fluxo: _fluxo,
        lancamentos: lancamentos,
        dre: dre,
        geradoEm: _hoje,
      );
      if (!mounted) return;
      await entregarPdf(context, bytes,
          nomeDoArquivo: RelatorioPdf.nomeDoRelatorio(de, ate));
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

  /// A DRE do mesmo período, para a seção "Demonstração do resultado" do
  /// PDF. Se não vier, o relatório sai sem a seção: é um complemento, e não
  /// pode impedir a exportação do que a tela já mostrou.
  Future<Dre?> _dreParaOPdf(DateTime de, DateTime ate) async {
    try {
      return await context
          .read<ApiService>()
          .financeiro
          .buscarDre(dataInicio: de, dataFim: ate);
    } on ApiException {
      return null;
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
            const SizedBox(height: 12),
            _cartaoDoResultado(),
            const SizedBox(height: 16),
            _painelDeFluxo(),
            const SizedBox(height: 16),
            _painelPorTipo(),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: _botaoExportar()),
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
        GridCol(span: 12, child: _cartaoDoResultado()),
        GridCol(span: 7, child: _painelDeFluxo()),
        GridCol(span: 5, child: _painelPorTipo()),
      ],
    );
  }

  Widget _seletorDePeriodo() {
    return SeletorDePeriodo(
      prefixoDaChave: 'relatorio-periodo',
      selecionado: _periodo,
      onSelecionar: (a) {
        setState(() => _periodo = a);
        _carregar();
      },
    );
  }

  /// O atalho para a pergunta que esta tela não responde. Aqui está o que
  /// passou pela carteira; "tive lucro?" depende dos custos que a pessoa
  /// informa, e mora na tela de resultado (RF13).
  Widget _cartaoDoResultado() {
    return Material(
      color: AppColors.tealSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('relatorio-ver-resultado'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => NavConfig.irParaSecao(context, AppRoutes.resultado),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  size: 22, color: AppColors.tealDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ver resultado (lucro/prejuízo)',
                        style: tsJakarta(13, FontWeight.w800,
                            color: AppColors.tealDeep)),
                    const SizedBox(height: 2),
                    Text(
                      _souLojista
                          ? 'O que as entregas renderam, descontado o que custaram'
                          : 'O que sobrou depois de combustível, manutenção e contas',
                      style: tsJakarta(11.5, FontWeight.w500,
                          color: AppColors.tealDeep),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.tealDeep),
            ],
          ),
        ),
      ),
    );
  }

  /// Os cartões do papel de quem abriu a tela, dois por linha. O que é do
  /// outro papel não aparece — nem zerado. A lista é a mesma do PDF
  /// ([ResumoFinanceiro.numerosPara]).
  Widget _cartoesDeResumo() {
    final cartoes = [
      for (final n in ResumoFinanceiro.numerosPara(_papel, _resumo))
        _cartao(n.rotulo, n.valor, _corDo(n.chave), Key('relatorio-${n.chave}')),
    ];

    final linhas = <Widget>[];
    for (var i = 0; i < cartoes.length; i += 2) {
      if (i > 0) linhas.add(const SizedBox(height: 10));
      linhas.add(Row(
        children: [
          Expanded(child: cartoes[i]),
          if (i + 1 < cartoes.length) ...[
            const SizedBox(width: 10),
            Expanded(child: cartoes[i + 1]),
          ],
        ],
      ));
    }
    return Column(children: linhas);
  }

  static Color _corDo(String chave) => switch (chave) {
        'recebido' || 'recarregado' || 'gorjetas' => AppColors.good,
        'retencoes' => AppColors.error,
        'disponivel' => AppColors.teal,
        'a-receber' || 'comprometido' => AppColors.muted,
        _ => AppColors.ink,
      };

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
      // O que compõe cada barra, dito para quem lê: reserva e liberação ficam
      // de fora (backend) porque são o dinheiro do lojista trocando de bolso.
      subtitle: _souLojista
          ? 'Recargas e estornos entrando; pagamentos a entregadores saindo'
          : 'Pagamentos recebidos entrando; saques e retenções saindo',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legenda(AppColors.good, 'Entrou na carteira'),
            const SizedBox(width: 14),
            _legenda(AppColors.error, 'Saiu da carteira'),
          ],
        ),
        const SizedBox(height: 10),
        _barras(maximo),
      ],
    );
  }

  Widget _legenda(Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(texto,
            style: tsJakarta(10.5, FontWeight.w500, color: AppColors.muted)),
      ],
    );
  }

  Widget _barras(double maximo) {
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

  /// A quebra na ordem de leitura do papel — a mesma do filtro do extrato
  /// ([TipoTransacao.filtraveisPara]). Um tipo fora da lista (um saque do
  /// lojista, um bônus) continua aparecendo, no fim: é dinheiro dele.
  Widget _painelPorTipo() {
    final ordem = TipoTransacao.filtraveisPara(_papel);
    int posicao(TotalPorTipo t) {
      final i = ordem.indexOf(t.tipo);
      return i < 0 ? ordem.length : i;
    }

    final itens = [...?_resumo?.porTipo]
      ..sort((a, b) => posicao(a).compareTo(posicao(b)));
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
      label: const Text('Exportar'),
      // Largura mínima zero, e não `Size.fromHeight`: aquela forma pede largura
      // infinita, o que no celular (numa coluna) esticava o botão como
      // desejado, mas no desktop — dentro de um Row, ao lado do seletor de
      // período — derrubava o layout inteiro da página. Quem quer o botão
      // esticado é o celular, e ele diz isso no próprio lugar onde o monta.
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
    );
  }

  /// O erro com a saída: "Tentar novamente" refaz a carga. O puxar para
  /// atualizar também refaz, mas no navegador e no desktop ninguém o
  /// descobre, e a tela ficava só com a mensagem.
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
          TextButton(
            key: const Key('relatorio-tentar-novamente'),
            onPressed: _carregando ? null : _carregar,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  static String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}
