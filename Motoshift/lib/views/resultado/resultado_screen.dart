import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/dre.dart';
import '../../models/extrato_filtro.dart';
import '../../models/lancamento_gerencial.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato_fiscal.dart';
import '../../utils/resumo_acessivel.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/seletor_de_periodo.dart';
import '../../widgets/situacao_do_resultado.dart';
import 'lancamento_form.dart';

/// Resultado do período — lucro ou prejuízo — numa DRE simplificada (RF13).
///
/// Uma tela para os dois papéis: o backend monta a demonstração de quem está
/// logado, e aqui as linhas são mostradas na ordem em que vieram. A tela não
/// soma nada: resultado, subtotais e indicadores chegam prontos.
///
/// <h3>O que ela responde</h3>
/// "Tive lucro?" — pergunta que os relatórios não respondiam, porque só
/// conheciam o que passou pela carteira. A resposta junta o extrato com o que
/// a pessoa informa aqui mesmo (combustível, manutenção, DAS, contas fixas; ou
/// a taxa de entrega que a loja cobrou). Cada linha diz de onde veio o número.
///
/// <h3>A situação nunca é só uma cor</h3>
/// A faixa do topo diz por extenso — "Lucro de R$ 1.240,00 no período" —, com
/// ícone e rótulo. O gráfico tem um resumo em texto para o leitor de tela, e o
/// resultado de cada mês leva o sinal além da cor.
///
/// <h3>O período</h3>
/// Os atalhos da tela de relatórios ([SeletorDePeriodo]) e mais um caminho:
/// tocar num mês do gráfico apura aquele mês. É como se chega ao mês
/// retrasado, que nenhum atalho cobre.
class ResultadoScreen extends StatefulWidget {
  const ResultadoScreen({super.key, this.agora});

  /// Fixa o "agora" — só os testes passam isto.
  final DateTime? agora;

  @override
  State<ResultadoScreen> createState() => _ResultadoScreenState();
}

class _ResultadoScreenState extends State<ResultadoScreen> {
  AtalhoDePeriodo? _atalho = AtalhoDePeriodo.mesAtual;

  /// Um mês escolhido no gráfico (o dia 1º dele); com ele, [_atalho] é nulo.
  DateTime? _mes;
  late int _anoDoGrafico = _hoje.year;

  Dre? _dre;
  List<LancamentoGerencial> _lancamentos = const [];
  List<MesDre> _meses = const [];
  List<CategoriaDeLancamento> _categorias = const [];

  bool _carregando = true;
  String? _erro;

  /// "Mostrar todas as linhas" da demonstração: as zeradas voltam.
  bool _mostrarLinhasZeradas = false;

  ScrollController? _rolagemDoGrafico;

  @override
  void dispose() {
    _rolagemDoGrafico?.dispose();
    super.dispose();
  }

  DateTime get _hoje => widget.agora ?? clock.now();

  TipoUsuario get _papel =>
      context.read<AuthService>().usuario?.tipo ?? TipoUsuario.motoboy;

  bool get _souLojista => _papel == TipoUsuario.lojista;

  (DateTime, DateTime) get _intervalo {
    final mes = _mes;
    if (mes != null) {
      // Dia 0 do mês seguinte é o último deste.
      final fim = DateTime(mes.year, mes.month + 1, 0);
      return (mes, fim.isAfter(_hoje) ? _hoje : fim);
    }
    return (_atalho ?? AtalhoDePeriodo.mesAtual).intervalo(_hoje);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final (de, ate) = _intervalo;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final api = context.read<ApiService>().financeiro;
      // Independentes: em paralelo, para a tela não abrir em três tempos.
      final respostas = await Future.wait([
        api.buscarDre(dataInicio: de, dataFim: ate),
        api.listarLancamentos(dataInicio: de, dataFim: ate),
        api.buscarDreMensal(ano: _anoDoGrafico),
        if (_categorias.isEmpty) api.buscarCategorias(),
      ]);
      if (!mounted) return;
      setState(() {
        _dre = respostas[0] as Dre;
        _lancamentos = respostas[1] as List<LancamentoGerencial>;
        _meses = respostas[2] as List<MesDre>;
        if (respostas.length > 3) {
          _categorias = respostas[3] as List<CategoriaDeLancamento>;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Erro ao carregar o resultado.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _escolherAtalho(AtalhoDePeriodo a) {
    setState(() {
      _atalho = a;
      _mes = null;
    });
    _carregar();
  }

  void _escolherMes(MesDre m) {
    setState(() {
      _mes = DateTime(_anoDoGrafico, m.mes, 1);
      _atalho = null;
    });
    _carregar();
  }

  void _mudarAno(int passo) {
    setState(() => _anoDoGrafico += passo);
    _carregar();
  }

  // ── Lançamentos ──────────────────────────────────────────────────────────


  Future<void> _abrirFormulario([LancamentoGerencial? existente]) async {
    final salvou = await abrirFormularioDeLancamento(
      context,
      categorias: _categorias,
      hoje: _hoje,
      existente: existente,
      turnos: turnosParaOLancamento(context),
    );
    if (salvou && mounted) {
      _avisar(existente == null ? 'Lançamento salvo.' : 'Lançamento atualizado.');
      await _carregar();
    }
  }

  Future<void> _excluir(LancamentoGerencial l) async {
    final id = l.id;
    if (id == null) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir lançamento',
            style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
        content: Text(
          l.recorrente
              ? '"${l.rotuloDaCategoria}" repete todo mês. Excluir tira este '
                  'lançamento de todos os meses, inclusive os que já passaram.'
              : 'Excluir "${l.rotuloDaCategoria}" de ${FormatoFiscal.moeda(l.valor)}? '
                  'Seu saldo não muda: o lançamento só existe no resultado.',
          style: tsJakarta(13, FontWeight.w400, color: AppColors.text, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('resultado-confirmar-exclusao'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    try {
      await context.read<ApiService>().financeiro.excluirLancamento(id);
      if (!mounted) return;
      _avisar('Lançamento excluído.');
      await _carregar();
    } on ApiException catch (e) {
      if (mounted) _avisar(e.message, erro: true);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? AppColors.error : AppColors.tealDeep,
      ),
    );
  }

  // ── Tela ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Resultado'),
      desktopTitle: 'Resultado',
      desktopSubtitle: _souLojista
          ? 'Lucro ou prejuízo da sua operação de entrega'
          : 'Lucro ou prejuízo do seu trabalho, com os custos que você informa',
      rotaDaSecao: AppRoutes.resultado,
      onAtualizar: _carregar,
      desktopBody: _desktop(),
      body: _mobile(),
    );
  }

  Widget _mobile() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _seletor(),
        const SizedBox(height: 14),
        if (_erro != null)
          _caixaDeErro(_erro!)
        else if (_dre == null)
          _carregandoTudo()
        else ...[
          _faixaDeSituacao(),
          if (_dre!.lancamentosManuais == 0) ...[
            const SizedBox(height: 12),
            _avisoSemLancamentos(),
          ],
          const SizedBox(height: 14),
          _painelDaDre(),
          const SizedBox(height: 14),
          _painelDeComparacao(),
          const SizedBox(height: 14),
          _indicadores(),
          const SizedBox(height: 14),
          _painelDoGrafico(),
          const SizedBox(height: 14),
          _painelDeLancamentos(),
        ],
      ],
    );
  }

  Widget _desktop() {
    if (_erro != null) return _caixaDeErro(_erro!);
    if (_dre == null) return _carregandoTudo();
    return ContentGrid(
      children: [
        GridCol(span: 12, child: _seletor()),
        GridCol(span: 12, child: _faixaDeSituacao()),
        if (_dre!.lancamentosManuais == 0)
          GridCol(span: 12, child: _avisoSemLancamentos()),
        GridCol(span: 7, child: _painelDaDre()),
        GridCol(
          span: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _painelDeComparacao(),
              const SizedBox(height: 16),
              _indicadores(),
            ],
          ),
        ),
        GridCol(span: 7, child: _painelDoGrafico()),
        GridCol(span: 5, child: _painelDeLancamentos()),
      ],
    );
  }

  Widget _carregandoTudo() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
        ),
      );

  // ── Período ──────────────────────────────────────────────────────────────

  Widget _seletor() {
    final mes = _mes;
    return SeletorDePeriodo(
      prefixoDaChave: 'resultado-periodo',
      selecionado: _atalho,
      onSelecionar: _escolherAtalho,
      // Na frente: a linha rola de lado, e o período em vigor não pode ficar
      // escondido depois dos atalhos.
      antes: [
        if (mes != null)
          InputChip(
            key: const Key('resultado-periodo-mes'),
            label: Text('${_nomeDoMes(mes.month)} de ${mes.year}'),
            selected: true,
            showCheckmark: false,
            deleteButtonTooltipMessage: 'Voltar ao mês atual',
            onDeleted: () => _escolherAtalho(AtalhoDePeriodo.mesAtual),
          ),
      ],
    );
  }

  // ── Faixa de situação ────────────────────────────────────────────────────

  /// A resposta, por extenso. Ícone, rótulo e frase dizem a mesma coisa que a
  /// cor — quem não distingue verde de vermelho lê "Prejuízo".
  Widget _faixaDeSituacao() {
    final dre = _dre!;
    final visual = VisualDaSituacao.de(dre.situacao);
    final (de, ate) = (dre.dataInicio, dre.dataFim);

    return Semantics(
      container: true,
      liveRegion: true,
      label: '${dre.frase}, de ${FormatoFiscal.data(de)} a ${FormatoFiscal.data(ate)}',
      excludeSemantics: true,
      child: Container(
        key: const Key('resultado-situacao'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: visual.fundo,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: visual.borda, width: 1.5),
        ),
        child: Row(
          children: [
            SeloDeSituacao(dre.situacao,
                chaveDoRotulo: const Key('resultado-situacao-rotulo')),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dre.frase,
                      key: const Key('resultado-frase'),
                      style: tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Text('${FormatoFiscal.data(de)} a ${FormatoFiscal.data(ate)}',
                      style: tsJakarta(12, FontWeight.w600, color: AppColors.mutedTexto)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sem nada informado, o "lucro" do entregador é só faturamento e o
  /// "prejuízo" do lojista é só custo. A tela diz isso antes de mostrar o
  /// número como se fosse a resposta.
  Widget _avisoSemLancamentos() {
    return Container(
      key: const Key('resultado-aviso-sem-lancamentos'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 19, color: AppColors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _souLojista
                  ? 'Este resultado só conhece o que você pagou pela plataforma. '
                      'Informe as taxas de entrega que cobrou para ver se a '
                      'operação se paga.'
                  : 'Este resultado só conhece o que você recebeu pela plataforma. '
                      'Informe seus custos — combustível, manutenção, DAS, contas '
                      'fixas — para ver o seu lucro de verdade.',
              style: tsJakarta(12, FontWeight.w600,
                  color: AppColors.onTertiary, height: 1.45),
            ),
          ),
          TextButton(
            key: const Key('resultado-informar'),
            onPressed: _categorias.isEmpty ? null : _abrirFormulario,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onTertiary,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Informar'),
          ),
        ],
      ),
    );
  }

  // ── A demonstração ───────────────────────────────────────────────────────

  /// As linhas zeradas ficam de fora (SCRUM-49): quem não tem retenção na
  /// fonte, seguro nem parcela lia seis "R$ 0,00" para achar os três números
  /// que importam. Subtotais e resultado aparecem sempre — são a conta. O
  /// backend continua mandando todas as linhas, e o link do fim as devolve.
  Widget _painelDaDre() {
    final dre = _dre!;
    final zeradas = dre.linhas.where((l) => l.zerada).length;
    final linhas = _mostrarLinhasZeradas
        ? dre.linhas
        : dre.linhas.where((l) => !l.zerada).toList();
    return PanelCard(
      key: const Key('resultado-dre'),
      title: 'Demonstração do resultado',
      subtitle: 'Regime de caixa: pelo dia do pagamento',
      padding: const EdgeInsets.all(16),
      gap: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in linhas) _linhaDaDre(l),
          if (zeradas > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('dre-mostrar-todas'),
                onPressed: () => setState(
                    () => _mostrarLinhasZeradas = !_mostrarLinhasZeradas),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealTexto,
                  minimumSize: const Size(0, 44),
                  padding: EdgeInsets.zero,
                  textStyle: tsJakarta(12.5, FontWeight.w700),
                ),
                child: Text(_mostrarLinhasZeradas
                    ? 'Ocultar linhas sem valor'
                    : 'Mostrar todas as linhas'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linhaDaDre(LinhaDre l) {
    final destaque = l.tipo != TipoDeLinhaDre.linha;
    final ehResultado = l.tipo == TipoDeLinhaDre.resultado;
    final peso = destaque ? FontWeight.w800 : FontWeight.w500;
    final origem = l.origem.rotulo;

    final conteudo = Padding(
      padding: EdgeInsets.symmetric(
          vertical: destaque ? 9 : 6, horizontal: ehResultado ? 10 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(destaque ? '= ${l.rotulo}' : l.rotuloComSinal,
                    style: tsJakarta(ehResultado ? 13.5 : 12.5, peso,
                        color: AppColors.ink)),
                if (origem.isNotEmpty)
                  Text(origem,
                      style: tsJakarta(10.5, FontWeight.w600,
                          color: AppColors.mutedTexto)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(FormatoFiscal.moeda(l.valor),
              style: tsBricolage(ehResultado ? 15 : 13, peso, color: AppColors.ink)),
        ],
      ),
    );

    // Uma linha, uma leitura: "(−) Combustível, informado por você, R$ 30,00".
    return MergeSemantics(
      child: Container(
        key: Key('dre-${l.chave}'),
        decoration: BoxDecoration(
          color: ehResultado ? AppColors.surface2 : null,
          borderRadius: ehResultado ? BorderRadius.circular(10) : null,
          border: destaque && !ehResultado
              ? const Border(top: BorderSide(color: AppColors.line, width: 1.5))
              : null,
        ),
        child: conteudo,
      ),
    );
  }

  // ── Comparação ───────────────────────────────────────────────────────────

  Widget _painelDeComparacao() {
    final dre = _dre!;
    final anterior = dre.anterior;
    final variacao = dre.variacaoResultado;
    if (anterior == null || variacao == null) return const SizedBox.shrink();

    // Em reais, e em palavras: "melhorou" e "piorou" não dependem de cor nem
    // de entender o que um percentual sobre prejuízo quer dizer.
    final (icone, texto) = variacao > 0
        ? (Icons.north_east_rounded, 'Melhorou ${FormatoFiscal.moeda(variacao)}')
        : variacao < 0
            ? (Icons.south_east_rounded, 'Piorou ${FormatoFiscal.moeda(variacao.abs())}')
            : (Icons.east_rounded, 'Igual ao período anterior');

    return PanelCard(
      key: const Key('resultado-comparacao'),
      title: 'Comparado ao período anterior',
      subtitle: '${FormatoFiscal.data(anterior.dataInicio)} a '
          '${FormatoFiscal.data(anterior.dataFim)}',
      padding: const EdgeInsets.all(16),
      gap: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Antes: ${_resultadoPorExtenso(anterior.resultado)}',
              style: tsJakarta(12.5, FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(icone, size: 18, color: AppColors.tealDeep),
              const SizedBox(width: 6),
              Expanded(
                child: Text(texto,
                    key: const Key('resultado-variacao'),
                    style: tsBricolage(15, FontWeight.w800, color: AppColors.ink)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _resultadoPorExtenso(double resultado) => resultado > 0
      ? 'lucro de ${FormatoFiscal.moeda(resultado)}'
      : resultado < 0
          ? 'prejuízo de ${FormatoFiscal.moeda(resultado.abs())}'
          : 'sem lucro nem prejuízo';

  // ── Indicadores ──────────────────────────────────────────────────────────

  Widget _indicadores() {
    final dre = _dre!;
    final cartoes = _souLojista
        ? [
            _indicador('custo-sobre-receita', 'Custo sobre a receita',
                _pct(dre.numero('custoSobreReceita')),
                ajuda: dre.numero('custoSobreReceita') == null
                    ? 'Informe as taxas cobradas'
                    : 'Do que você cobrou, quanto foi para a entrega'),
            _indicador('turnos', 'Turnos finalizados',
                '${dre.inteiro('turnosFinalizados') ?? 0}'),
            _indicador('custo-por-turno', 'Custo médio por turno',
                _moedaOuTraco(dre.numero('custoMedioPorTurno'))),
            _indicadorDeResultado('resultado-por-turno', 'turno',
                dre.numero('resultadoPorTurno'),
                positivo: 'Resultado'),
            _indicador('gorjetas', 'Gorjetas dadas',
                _moedaOuTraco(dre.numero('gorjetasDadas'))),
          ]
        : [
            _indicador('margem', 'Margem líquida', _pct(dre.numero('margemLiquida')),
                ajuda: 'Do que entrou, quanto ficou'),
            _indicador('turnos', 'Turnos pagos', '${dre.inteiro('turnosPagos') ?? 0}'),
            _indicador('horas', 'Horas trabalhadas',
                _horas(dre.numero('horasTrabalhadas'))),
            _indicadorDeResultado(
                'lucro-por-hora', 'hora', dre.numero('lucroPorHora')),
            _indicadorDeResultado(
                'lucro-por-turno', 'turno', dre.numero('lucroPorTurno')),
            _indicador('custo-por-km', 'Custo por km',
                _moedaOuTraco(dre.numero('custoPorKm')),
                ajuda: dre.numero('custoPorKm') == null
                    ? 'Informe os km nos lançamentos'
                    : 'Combustível e manutenção sobre os km informados'),
            _indicador(
                'ponto-de-equilibrio',
                'Ponto de equilíbrio',
                switch (dre.inteiro('pontoDeEquilibrioTurnos')) {
                  null => '—',
                  1 => '1 turno',
                  final n => '$n turnos',
                },
                ajuda: dre.inteiro('pontoDeEquilibrioTurnos') == null
                    ? _comMaiuscula(dre.texto('pontoDeEquilibrioMotivo') ?? '')
                    : 'Turnos para pagar as despesas fixas'),
          ];

    final linhas = <Widget>[];
    for (var i = 0; i < cartoes.length; i += 2) {
      if (i > 0) linhas.add(const SizedBox(height: 10));
      linhas.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: cartoes[i]),
            const SizedBox(width: 10),
            Expanded(
                child: i + 1 < cartoes.length ? cartoes[i + 1] : const SizedBox.shrink()),
          ],
        ),
      ));
    }
    return Column(children: linhas);
  }

  /// Um indicador que é resultado dividido por alguma coisa — por hora, por
  /// turno. Negativo, ele muda de nome: "Prejuízo por hora", com o valor sem
  /// sinal. "Lucro por hora: −R$ 12,00" obrigava a ler o sinal para entender
  /// o rótulo ao contrário (SCRUM-49). O texto e a cor seguem a faixa de
  /// situação; a cor só reforça o que o rótulo já diz.
  Widget _indicadorDeResultado(String chave, String por, double? valor,
      {String positivo = 'Lucro'}) {
    if (valor == null) return _indicador(chave, '$positivo por $por', '—');
    if (valor < 0) {
      return _indicador(chave, 'Prejuízo por $por', FormatoFiscal.moeda(valor.abs()),
          cor: VisualDaSituacao.prejuizo.cor);
    }
    return _indicador(chave, '$positivo por $por', FormatoFiscal.moeda(valor),
        cor: valor > 0 ? VisualDaSituacao.lucro.cor : null);
  }

  Widget _indicador(String chave, String rotulo, String valor,
      {String? ajuda, Color? cor}) {
    return MergeSemantics(
      child: Container(
        key: Key('indicador-$chave'),
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
                style: tsJakarta(11, FontWeight.w700, color: AppColors.mutedTexto)),
            const SizedBox(height: 4),
            Text(valor,
                style: tsBricolage(17, FontWeight.w800, color: cor ?? AppColors.ink)),
            if (ajuda != null && ajuda.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(ajuda,
                  style: tsJakarta(10.5, FontWeight.w500,
                      color: AppColors.mutedTexto, height: 1.35)),
            ],
          ],
        ),
      ),
    );
  }

  static String _pct(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  static String _horas(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1).replaceAll('.', ',')} h';

  static String _moedaOuTraco(double? v) => v == null ? '—' : FormatoFiscal.moeda(v);

  static String _comMaiuscula(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // ── Gráfico mensal ───────────────────────────────────────────────────────

  Widget _painelDoGrafico() {
    return PanelCard(
      key: const Key('resultado-grafico'),
      title: 'Mês a mês',
      subtitle: 'Toque num mês para ver a DRE dele',
      padding: const EdgeInsets.all(16),
      gap: 12,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('resultado-ano-anterior'),
            tooltip: 'Ano anterior',
            visualDensity: VisualDensity.compact,
            onPressed: _carregando ? null : () => _mudarAno(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('$_anoDoGrafico',
              style: tsJakarta(13, FontWeight.w800, color: AppColors.ink)),
          IconButton(
            key: const Key('resultado-ano-seguinte'),
            tooltip: 'Próximo ano',
            visualDensity: VisualDensity.compact,
            onPressed: _carregando || _anoDoGrafico >= _hoje.year
                ? null
                : () => _mudarAno(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      child: _grafico(),
    );
  }

  Widget _grafico() {
    if (_meses.every((m) => m.semMovimento)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('Sem movimento em $_anoDoGrafico.',
              style: tsJakarta(12.5, FontWeight.w500, color: AppColors.mutedTexto)),
        ),
      );
    }

    final maximo = _meses
        .map((m) => m.receita > m.custos ? m.receita : m.custos)
        .fold<double>(0, (a, b) => a > b ? a : b);

    // O resumo é do gráfico inteiro; cada mês continua sendo um botão com o
    // próprio nome, por isso `explicitChildNodes` e não `excludeSemantics`.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: resumoDoResultadoMensal(_anoDoGrafico, [
        for (final m in _meses)
          (rotulo: m.rotulo, receita: m.receita, custos: m.custos, resultado: m.resultado),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _legenda(AppColors.teal, 'Receita'),
                _legenda(AppColors.amber, 'Custos'),
                Text('Número: resultado do mês (+ lucro, − prejuízo)',
                    style: tsJakarta(10.5, FontWeight.w600, color: AppColors.mutedTexto)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: LayoutBuilder(
              builder: (context, limites) {
                const larguraMinima = 50.0;
                final cabem = limites.maxWidth >= larguraMinima * _meses.length;
                if (cabem) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final m in _meses) Expanded(child: _colunaDoMes(m, maximo)),
                    ],
                  );
                }
                // No celular os doze meses não cabem: a lista rola, e abre
                // com o mês atual à vista — janeiro raramente é o assunto.
                _rolagemDoGrafico ??= ScrollController(
                  initialScrollOffset: ((_hoje.month - 5) * larguraMinima).clamp(
                      0.0, larguraMinima * _meses.length - limites.maxWidth),
                );
                return ListView(
                  controller: _rolagemDoGrafico,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final m in _meses)
                      SizedBox(width: larguraMinima, child: _colunaDoMes(m, maximo)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _legenda(Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(texto, style: tsJakarta(10.5, FontWeight.w600, color: AppColors.mutedTexto)),
      ],
    );
  }

  Widget _colunaDoMes(MesDre m, double maximo) {
    final noFuturo = _anoDoGrafico == _hoje.year && m.mes > _hoje.month;
    final escolhido = _mes != null && _mes!.year == _anoDoGrafico && _mes!.month == m.mes;

    // O sinal vai escrito: a cor só reforça.
    final resultado = m.semMovimento
        ? '—'
        : '${m.resultado > 0 ? '+' : m.resultado < 0 ? '−' : ''}'
            '${m.resultado.abs().round()}';
    final corDoResultado = m.resultado > 0
        ? const Color(0xFF0B5C43)
        : m.resultado < 0
            ? const Color(0xFF8C1212)
            : AppColors.mutedTexto;

    final coluna = Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: escolhido ? AppColors.tealSoft : null,
        borderRadius: BorderRadius.circular(8),
        border: escolhido ? Border.all(color: AppColors.teal, width: 1.5) : null,
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _barra(m.receita, maximo, AppColors.teal),
                const SizedBox(width: 3),
                _barra(m.custos, maximo, AppColors.amber),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(m.rotulo,
              style: tsJakarta(10.5, FontWeight.w700, color: AppColors.mutedTexto)),
          const SizedBox(height: 1),
          Text(resultado,
              style: tsJakarta(10.5, FontWeight.w800, color: corDoResultado)),
        ],
      ),
    );

    final descricao = m.semMovimento
        ? '${_nomeDoMes(m.mes)}: sem movimento'
        : '${_nomeDoMes(m.mes)}: receita ${reaisFalados(m.receita)}, '
            'custos ${reaisFalados(m.custos)}, ${resultadoFalado(m.resultado)}';

    return Semantics(
      container: true,
      button: !noFuturo,
      selected: escolhido,
      label: descricao,
      hint: noFuturo ? null : 'Ver a DRE deste mês',
      onTap: noFuturo ? null : () => _escolherMes(m),
      excludeSemantics: true,
      child: InkWell(
        key: Key('resultado-mes-${m.mes}'),
        borderRadius: BorderRadius.circular(8),
        onTap: noFuturo ? null : () => _escolherMes(m),
        child: coluna,
      ),
    );
  }

  Widget _barra(double valor, double maximo, Color cor) {
    return LayoutBuilder(
      builder: (context, limites) {
        final altura = limites.maxHeight;
        // Altura mínima de 2px: "quase zero" não é "nada".
        final h = maximo <= 0 || valor <= 0
            ? 2.0
            : (valor / maximo * altura).clamp(2.0, altura);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 9,
            height: h,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: valor <= 0 ? 0.3 : 1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
        );
      },
    );
  }

  static String _nomeDoMes(int mes) => const [
        'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
        'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
      ][mes - 1];

  // ── Lançamentos ──────────────────────────────────────────────────────────

  Widget _painelDeLancamentos() {
    return PanelCard(
      key: const Key('resultado-lancamentos'),
      title: 'O que você informou',
      subtitle: 'Fora da plataforma, neste período',
      padding: const EdgeInsets.all(16),
      gap: 10,
      trailing: TextButton.icon(
        key: const Key('resultado-novo-lancamento'),
        onPressed: _categorias.isEmpty ? null : _abrirFormulario,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Informar'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.tealDeep,
          minimumSize: const Size(0, 44),
        ),
      ),
      child: _lancamentos.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Nada informado neste período.',
                    style: tsJakarta(12.5, FontWeight.w500, color: AppColors.mutedTexto)),
              ),
            )
          : Column(children: [for (final l in _lancamentos) _itemDeLancamento(l)]),
    );
  }

  Widget _itemDeLancamento(LancamentoGerencial l) {
    final vezes = l.ocorrenciasNoPeriodo ?? 1;
    // Data futura: está aqui para poder ser conferido e corrigido, e diz que
    // ainda não entrou na conta.
    final quando = l.aindaNaoConta
        ? (l.recorrente
            ? 'Começa em ${FormatoFiscal.data(l.data)} · todo dia ${l.data.day} · ainda não conta'
            : 'Data futura: ${FormatoFiscal.data(l.data)} · ainda não conta')
        : l.recorrente
            ? 'Todo dia ${l.data.day}${vezes > 1 ? ' · $vezes vezes no período' : ''}'
            : FormatoFiscal.data(l.data);
    final detalhe = [
      quando,
      if ((l.descricao ?? '').isNotEmpty) l.descricao!,
    ].join(' · ');

    return Padding(
      key: Key('lancamento-${l.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.rotuloDaCategoria,
                      style: tsJakarta(12.5, FontWeight.w700, color: AppColors.ink)),
                  Text(detalhe,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tsJakarta(11, FontWeight.w500, color: AppColors.mutedTexto)),
                  // O sinal vem da categoria, e vai escrito.
                  Text('${l.soma ? '+' : '−'} ${FormatoFiscal.moeda(l.valorExibido)}',
                      style: tsBricolage(13, FontWeight.w800, color: AppColors.ink)),
                ],
              ),
            ),
          ),
          IconButton(
            key: Key('lancamento-editar-${l.id}'),
            tooltip: 'Editar ${l.rotuloDaCategoria}',
            onPressed: () => _abrirFormulario(l),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          IconButton(
            key: Key('lancamento-excluir-${l.id}'),
            tooltip: 'Excluir ${l.rotuloDaCategoria}',
            onPressed: () => _excluir(l),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  // ── Erro ─────────────────────────────────────────────────────────────────

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
                style: tsJakarta(12.5, FontWeight.w600, color: AppColors.error)),
          ),
          TextButton(
            key: const Key('resultado-tentar-novamente'),
            onPressed: _carregando ? null : _carregar,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
