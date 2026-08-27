import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/desktop/panel_card.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_pill.dart';
import '../avaliacao/avaliacao_screen.dart';

class HistoricoTurnosScreen extends StatefulWidget {
  const HistoricoTurnosScreen({super.key});

  @override
  State<HistoricoTurnosScreen> createState() =>
      _HistoricoTurnosScreenState();
}

class _HistoricoTurnosScreenState extends State<HistoricoTurnosScreen> {
  List<Turno> _turnos = const [];
  Set<int> _turnosAvaliados = const {};
  bool _carregando = true;
  String _filtro = 'todos';

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

    setState(() => _carregando = true);
    try {
      final isLojista = auth.usuario?.tipo == TipoUsuario.lojista;
      final lista = isLojista
          ? await api.listarTurnosLojista(id)
          : await api.listarMeusTurnos(id);
      final avaliados = await api.buscarTurnosAvaliados(id);
      if (!mounted) return;
      setState(() {
        // Tudo que não está mais em jogo entra no histórico — por negação,
        // e não listando os status um a um. Quando `expirado` foi criado
        // (SCRUM-19) a lista antiga só aceitava finalizado|cancelado, então o
        // backend expirava o turno e ele sumia da interface: não aparecia em
        // "Abertos", nem em "Finalizados", nem aqui. Com `!ativo` o próximo
        // status terminal já nasce visível.
        _turnos = lista.where((t) => !t.status.ativo).toList()
          ..sort((a, b) => b.dataInicio.compareTo(a.dataInicio));
        _turnosAvaliados = avaliados.toSet();
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // ── Filtros ──────────────────────────────────────────────────────────────

  bool _precisaAvaliar(Turno t) =>
      t.status == StatusTurno.finalizado &&
      !_turnosAvaliados.contains(t.id);

  bool _aguardandoPagamento(Turno t) =>
      t.status == StatusTurno.finalizado &&
      t.pagamentoStatus == PagamentoStatus.pendente;

  /// Lojista precisa confirmar que enviou o pagamento.
  bool _lojistaPrecisaConfirmar(Turno t) =>
      _aguardandoPagamento(t) && !t.lojistaJaConfirmou;

  /// Motoboy precisa confirmar que recebeu o pagamento.
  bool _motoboyPrecisaConfirmar(Turno t) =>
      _aguardandoPagamento(t) && !t.motoboyJaConfirmou;

  List<Turno> get _filtrados {
    switch (_filtro) {
      case 'avaliar':
        return _turnos.where(_precisaAvaliar).toList();
      case 'pagamento':
        return _turnos.where(_aguardandoPagamento).toList();
      case 'concluidos':
        return _turnos
            .where((t) =>
                t.status == StatusTurno.finalizado &&
                t.pagamentoStatus == PagamentoStatus.pago)
            .toList();
      case 'cancelados':
        return _turnos
            .where((t) => t.status == StatusTurno.cancelado)
            .toList();
      case 'expirados':
        return _turnos
            .where((t) => t.status == StatusTurno.expirado)
            .toList();
      default:
        return _turnos;
    }
  }

  int get _qtdAvaliar => _turnos.where(_precisaAvaliar).length;
  int get _qtdPagamento => _turnos.where(_aguardandoPagamento).length;
  int get _qtdConcluidos => _turnos
      .where((t) =>
          t.status == StatusTurno.finalizado &&
          t.pagamentoStatus == PagamentoStatus.pago)
      .length;
  int get _qtdCancelados =>
      _turnos.where((t) => t.status == StatusTurno.cancelado).length;
  int get _qtdExpirados =>
      _turnos.where((t) => t.status == StatusTurno.expirado).length;

  double get _valorPendente => _turnos
      .where(_aguardandoPagamento)
      .fold(0.0, (acc, t) => acc + t.valorEstimado);

  double get _totalGanho => _turnos
      .where((t) =>
          t.status == StatusTurno.finalizado &&
          t.pagamentoStatus == PagamentoStatus.pago)
      .fold(0.0, (acc, t) => acc + t.valorEstimado);

  // ── Ações ────────────────────────────────────────────────────────────────

  Future<void> _abrirAvaliacao(Turno t) async {
    final auth = context.read<AuthService>();
    final isLojista = auth.usuario?.tipo == TipoUsuario.lojista;
    final avaliadorId = auth.usuario?.id;
    if (avaliadorId == null || t.id == null) return;

    final avaliadoId = isLojista ? (t.motoboyId ?? -1) : t.lojistId;
    if (avaliadoId < 0) return;

    await Navigator.pushNamed(
      context,
      AppRoutes.avaliacao,
      arguments: AvaliacaoArgs(
        turnoId: t.id!,
        avaliadorId: avaliadorId,
        avaliadoId: avaliadoId,
        nomeAvaliado: t.titulo,
      ),
    );
    _carregar();
  }

  Future<void> _confirmarPagamento(Turno t, {required bool isLojista}) async {
    if (t.id == null) return;
    final auth = context.read<AuthService>();
    final id = auth.usuario?.id;
    if (id == null) return;

    final titulo = isLojista
        ? 'Confirmar pagamento enviado'
        : 'Confirmar recebimento';
    final mensagem = isLojista
        ? 'Você está declarando que enviou o pagamento ao motoboy.\n\n'
            'O motoboy precisará confirmar o recebimento para que o valor '
            'seja efetivamente creditado na carteira dele.'
        : 'Você está declarando que recebeu o pagamento do lojista.\n\n'
            'Quando o lojista também confirmar, o valor será creditado '
            'na sua carteira.';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo,
            style: tsBricolage(17, FontWeight.w800,
                color: AppColors.ink)),
        content: Text(mensagem,
            style: tsJakarta(13, FontWeight.w400,
                color: AppColors.muted, height: 1.4)),
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
    if (confirmar != true || !mounted) return;

    try {
      final api = context.read<ApiService>();
      final atualizado = isLojista
          ? await api.confirmarPagamentoLojista(t.id!, id,
              motoboyId: t.motoboyId)
          : await api.confirmarRecebimentoMotoboy(t.id!, id);
      if (!mounted) return;
      final efetivado =
          atualizado.pagamentoStatus == PagamentoStatus.pago;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(efetivado
              ? 'Pagamento efetivado — ambas as partes confirmaram!'
              : isLojista
                  ? 'Confirmação registrada. Aguardando o motoboy.'
                  : 'Confirmação registrada. Aguardando o lojista.'),
          backgroundColor:
              efetivado ? AppColors.good : AppColors.teal,
        ),
      );
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // Painel do lojista para pagar cada entregador de um turno multi-vaga.
  Future<void> _abrirInscritosPagamento(Turno t) async {
    if (t.id == null) return;
    final auth = context.read<AuthService>();
    final lojistaId = auth.usuario?.id;
    if (lojistaId == null) return;
    final api = context.read<ApiService>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: api.listarInscritos(t.id!),
              builder: (ctx, snap) {
                final inscritos = snap.data ?? [];
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                      18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Pagamento por entregador',
                          style: tsBricolage(17, FontWeight.w800,
                              color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('${t.vagasPreenchidas} de ${t.vagas} vagas • R\$ '
                          '${t.valorEstimado.toStringAsFixed(0)} cada',
                          style: tsJakarta(12, FontWeight.w400,
                              color: AppColors.muted)),
                      const SizedBox(height: 14),
                      if (snap.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.teal)),
                        )
                      else if (inscritos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('Nenhum entregador inscrito.',
                              style: tsJakarta(13, FontWeight.w400,
                                  color: AppColors.muted)),
                        )
                      else
                        ...inscritos.map((ins) => _linhaInscrito(
                            ctx, setSheet, t, lojistaId, api, ins)),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    _carregar();
  }

  Widget _linhaInscrito(
      BuildContext ctx,
      void Function(void Function()) setSheet,
      Turno t,
      int lojistaId,
      ApiService api,
      Map<String, dynamic> ins) {
    final nome = (ins['nome'] ?? 'Entregador').toString();
    final pago = ins['pagamentoStatus'] == 'pago';
    final lojistaConfirmou = ins['lojistaConfirmou'] == true;
    final motoboyId = (ins['motoboyId'] as num?)?.toInt();

    final String etiqueta;
    final Color cor;
    if (pago) {
      etiqueta = 'Pago';
      cor = AppColors.good;
    } else if (lojistaConfirmou) {
      etiqueta = 'Aguardando entregador';
      cor = AppColors.teal;
    } else {
      etiqueta = 'A pagar';
      cor = AppColors.muted;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome,
                    style: tsJakarta(13, FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(etiqueta,
                    style: tsJakarta(11, FontWeight.w600, color: cor)),
              ],
            ),
          ),
          if (!pago && !lojistaConfirmou && motoboyId != null)
            GestureDetector(
              onTap: () async {
                try {
                  await api.confirmarPagamentoLojista(t.id!, lojistaId,
                      motoboyId: motoboyId);
                  setSheet(() {});
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Erro: $e'),
                        backgroundColor: AppColors.error),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('Confirmar',
                    style: tsJakarta(11, FontWeight.w700,
                        color: Colors.white)),
              ),
            )
          else
            Icon(pago ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
                color: cor, size: 20),
        ],
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Histórico de turnos'),
      desktopTitle: 'Histórico de turnos',
      desktopSubtitle: _subtituloDesktop(),
      // Também é sub-página do Perfil, e /historico-turnos não é item de
      // sidebar: apontar para ele deixava o desktop sem nada destacado.
      desktopSelectedRoute: AppRoutes.perfil,
      desktopBody: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : _turnos.isEmpty
              ? _buildVazio()
              : _buildDesktop(),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : _turnos.isEmpty
              ? _buildVazio()
              : _buildLista(),
    );
  }

  // ── Desktop — KPIs + tabela ──────────────────────────────────────────────

  String _subtituloDesktop() {
    if (_carregando) return 'Carregando histórico…';
    final n = _turnos.length;
    if (n == 0) return 'Nenhum turno encerrado ainda';
    final maisAntigo = _turnos.last.dataInicio;
    return '$n ${n == 1 ? 'turno' : 'turnos'} desde '
        '${DateFormat('MMMM \'de\' y', 'pt_BR').format(maisAntigo)}';
  }

  int get _qtdFinalizados =>
      _turnos.where((t) => t.status == StatusTurno.finalizado).length;

  double get _horasRodadas => _turnos
      .where((t) => t.status == StatusTurno.finalizado)
      .fold(0.0, (acc, t) => acc + t.duracao.inMinutes / 60);

  Widget _buildDesktop() {
    final isLojista =
        context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;
    final total = _turnos.length;
    final pctConclusao =
        total == 0 ? 0 : (_qtdFinalizados / total * 100).round();
    final mediaTurno =
        _qtdFinalizados == 0 ? 0.0 : _totalGanho / _qtdFinalizados;
    final mediaHoras =
        _qtdFinalizados == 0 ? 0.0 : _horasRodadas / _qtdFinalizados;

    return ContentGrid(
      children: [
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: 'Turnos concluídos',
            value: '$_qtdFinalizados',
            sub: '$pctConclusao% de conclusão',
          ),
        ),
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: isLojista ? 'Total pago' : 'Total recebido',
            value: 'R\$ ${_totalGanho.toStringAsFixed(0)}',
            sub: 'média R\$ ${mediaTurno.toStringAsFixed(0)}',
            subColor: AppColors.muted,
          ),
        ),
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: 'Cancelados',
            value: '$_qtdCancelados',
            // Os expirados entram como subtexto: não cabe um quinto card no
            // grid de 12 colunas, mas o estado precisa aparecer em algum lugar
            // desta linha — senão volta a ser invisível.
            sub: _qtdExpirados > 0
                ? '+ $_qtdExpirados '
                    '${_qtdExpirados == 1 ? 'expirado' : 'expirados'}'
                : (_qtdCancelados == 0 ? 'nenhum' : 'no período'),
            subColor: _qtdCancelados > 0 || _qtdExpirados > 0
                ? AppColors.amber
                : AppColors.muted,
          ),
        ),
        GridCol(
          span: 3,
          child: StatCard(
            size: StatCardSize.large,
            label: 'Horas rodadas',
            value: '${_horasRodadas.toStringAsFixed(0)} h',
            sub: '${mediaHoras.toStringAsFixed(1).replaceAll('.', ',')} h '
                'por turno',
            subColor: AppColors.muted,
          ),
        ),
        GridCol(
          span: 12,
          child: PanelCard(
            padding: const EdgeInsets.all(22),
            gap: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFiltrosDesktop(isLojista),
                const SizedBox(height: 14),
                _buildTabela(isLojista),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltrosDesktop(bool isLojista) {
    final opcoes = [
      ('todos', 'Todos', _turnos.length),
      ('avaliar', 'A avaliar', _qtdAvaliar),
      ('pagamento', isLojista ? 'A pagar' : 'A receber', _qtdPagamento),
      ('concluidos', 'Concluídos', _qtdConcluidos),
      ('cancelados', 'Cancelados', _qtdCancelados),
      ('expirados', 'Expirados', _qtdExpirados),
    ];

    return Row(
      children: [
        for (final op in opcoes) ...[
          InkWell(
            onTap: () => setState(() => _filtro = op.$1),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _filtro == op.$1 ? AppColors.teal : AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(
                    op.$2,
                    style: tsJakarta(12, FontWeight.w700,
                        color: _filtro == op.$1
                            ? Colors.white
                            : AppColors.muted),
                  ),
                  if (op.$3 > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${op.$3}',
                      style: tsJakarta(11, FontWeight.w800,
                          color: _filtro == op.$1
                              ? Colors.white70
                              : AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// Colunas: turno · data · região · status · valor.
  ///
  /// O artboard traz "LOJISTA" na terceira coluna, mas o turno só carrega
  /// `lojistId` — o nome exigiria uma busca por turno. Fica a região, que é
  /// dado que a lista já tem.
  Widget _buildTabela(bool isLojista) {
    const flexes = [26, 16, 20, 15, 14];
    final linhas = _filtrados;

    Widget celula(int i, Widget filho, {bool fim = false}) => Expanded(
          flex: flexes[i],
          child: Align(
            alignment: fim ? Alignment.centerRight : Alignment.centerLeft,
            child: filho,
          ),
        );

    Widget cabecalho(String texto) => Text(
          texto,
          style: tsJakarta(10.5, FontWeight.w700, color: AppColors.muted)
              .copyWith(letterSpacing: 10.5 * .08),
        );

    if (linhas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('Nenhum turno nesse filtro.',
              style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.line, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              celula(0, cabecalho('TURNO')),
              celula(1, cabecalho('DATA')),
              celula(2, cabecalho('REGIÃO')),
              celula(3, cabecalho('STATUS')),
              celula(4, cabecalho('VALOR'), fim: true),
            ],
          ),
        ),
        for (final t in linhas) _buildLinhaTabela(t, isLojista, celula),
      ],
    );
  }

  Widget _buildLinhaTabela(
    Turno t,
    bool isLojista,
    Widget Function(int, Widget, {bool fim}) celula,
  ) {
    // Cancelado e expirado terminam sem entrega e sem dinheiro trocando de
    // mão: mesmo tratamento visual (apagado), rótulo próprio de cada um.
    final semEntrega = t.status == StatusTurno.cancelado ||
        t.status == StatusTurno.expirado;
    final pago = t.pagamentoStatus == PagamentoStatus.pago;

    final (String rotulo, PillVariant variante) = semEntrega
        ? (t.status.label, PillVariant.ghost)
        : pago
            ? ('Pago', PillVariant.good)
            : _aguardandoPagamento(t)
                ? (isLojista ? 'A pagar' : 'A receber', PillVariant.amber)
                : ('Finalizado', PillVariant.ghost);

    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        isLojista ? AppRoutes.turnoLojista : AppRoutes.detalheTurno,
        arguments: t,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            celula(
              0,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tsJakarta(13, FontWeight.w700,
                          color: semEntrega ? AppColors.muted : AppColors.text)),
                  Text(
                    '${t.horarioFormatado} · '
                    '${t.raioEntregaKm.toStringAsFixed(0)} km',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tsJakarta(11, FontWeight.w400, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            celula(
              1,
              Text(DateFormat('dd/MM/yyyy', 'pt_BR').format(t.dataInicio),
                  style: tsJakarta(12.5, FontWeight.w400,
                      color: AppColors.muted)),
            ),
            celula(
              2,
              Text(t.regiao,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tsJakarta(12.5, FontWeight.w400, color: AppColors.text)),
            ),
            celula(3, StatusPill(label: rotulo, variant: variante)),
            celula(
              4,
              Text(
                'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                style: tsBricolage(15, FontWeight.w800,
                    color: semEntrega ? AppColors.muted : AppColors.ink),
              ),
              fim: true,
            ),
          ],
        ),
      ),
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
              'Turnos concluídos, cancelados ou expirados aparecem aqui.',
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
    final isLojista =
        context.read<AuthService>().usuario?.tipo == TipoUsuario.lojista;

    return RefreshIndicator(
      onRefresh: _carregar,
      color: AppColors.teal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
        children: [
          _buildResumo(isLojista),
          const SizedBox(height: 16),
          _buildFiltros(isLojista),
          const SizedBox(height: 14),
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
      ),
    );
  }

  Widget _buildResumo(bool isLojista) {
    final labelPendente =
        isLojista ? 'A PAGAR' : 'A RECEBER';

    return Row(
      children: [
        Expanded(
          child: _statCell(
            label: 'A AVALIAR',
            value: '$_qtdAvaliar',
            iconData: Icons.star_outline_rounded,
            highlight: _qtdAvaliar > 0,
            color: _qtdAvaliar > 0 ? AppColors.amber : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCell(
            label: labelPendente,
            value: 'R\$ ${_valorPendente.toStringAsFixed(0)}',
            iconData: Icons.schedule_rounded,
            highlight: _qtdPagamento > 0,
            color: _qtdPagamento > 0 ? AppColors.amber : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCell(
            label: isLojista ? 'GASTO PAGO' : 'RECEBIDO',
            value: 'R\$ ${_totalGanho.toStringAsFixed(0)}',
            iconData: Icons.check_circle_outline_rounded,
            highlight: true,
          ),
        ),
      ],
    );
  }

  Widget _statCell({
    required String label,
    required String value,
    required IconData iconData,
    bool highlight = false,
    Color? color,
  }) {
    final accent = color ?? AppColors.tealDeep;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 11),
      decoration: BoxDecoration(
        color: highlight
            ? (color == AppColors.amber
                ? AppColors.amberSoft
                : AppColors.tealSoft)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight ? accent.withOpacity(0.4) : AppColors.line,
            width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(iconData,
                  size: 13,
                  color: highlight ? accent : AppColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(8.5, FontWeight.w700,
                        color:
                            highlight ? accent : AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: tsBricolage(16, FontWeight.w800,
                    color: highlight ? accent : AppColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(bool isLojista) {
    final pagamentoLabel = isLojista ? 'A pagar' : 'A receber';
    final opcoes = [
      ('todos', 'Todos', _turnos.length),
      ('avaliar', 'A avaliar', _qtdAvaliar),
      ('pagamento', pagamentoLabel, _qtdPagamento),
      ('concluidos', 'Concluídos', _qtdConcluidos),
      ('cancelados', 'Cancelados', _qtdCancelados),
      ('expirados', 'Expirados', _qtdExpirados),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opcoes.map((op) {
          final sel = _filtro == op.$1;
          final count = op.$3;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => _filtro = op.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? AppColors.teal : AppColors.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: sel ? AppColors.teal : AppColors.line,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      op.$2,
                      style: tsJakarta(12, FontWeight.w700,
                          color: sel ? Colors.white : AppColors.muted),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: sel
                              ? Colors.white24
                              : AppColors.surface3,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$count',
                          style: tsJakarta(9.5, FontWeight.w800,
                              color: sel
                                  ? Colors.white
                                  : AppColors.muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTurnoCard(Turno t, bool isLojista) {
    final dataFmt =
        DateFormat('dd/MM/yyyy', 'pt_BR').format(t.dataInicio);
    final precisaAvaliar = _precisaAvaliar(t);
    final aguardaPagto = _aguardandoPagamento(t);

    // Determina label/cor da pill conforme estado de confirmação
    PillVariant pill;
    String pillLabel;
    if (t.status == StatusTurno.cancelado ||
        t.status == StatusTurno.expirado) {
      pill = PillVariant.ghost;
      pillLabel = t.status.label;
    } else if (aguardaPagto) {
      pill = PillVariant.amber;
      if (isLojista) {
        pillLabel = t.lojistaJaConfirmou
            ? 'Aguardando motoboy'
            : 'A confirmar';
      } else {
        pillLabel = t.motoboyJaConfirmou
            ? 'Aguardando lojista'
            : (t.lojistaJaConfirmou
                ? 'Confirme recebimento'
                : 'A receber');
      }
    } else if (t.pagamentoStatus == PagamentoStatus.pago) {
      pill = PillVariant.good;
      pillLabel = 'Pago';
    } else {
      pill = PillVariant.ghost;
      pillLabel = 'Finalizado';
    }

    final podeConfirmarPgto = aguardaPagto &&
        (isLojista
            ? _lojistaPrecisaConfirmar(t)
            : _motoboyPrecisaConfirmar(t));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ShiftCard(
            horario: dataFmt,
            name: t.titulo,
            meta: [t.regiao],
            value: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
            iconData: isLojista
                ? Icons.store_outlined
                : Icons.two_wheeler_outlined,
            pillLabel: pillLabel,
            pillVariant: pill,
            onTap: () => Navigator.pushNamed(
              context,
              isLojista
                  ? AppRoutes.turnoLojista
                  : AppRoutes.detalheTurno,
              arguments: t,
            ),
          ),
          if (aguardaPagto && !podeConfirmarPgto)
            _buildEsperandoOutraParte(t, isLojista),
          if (precisaAvaliar || podeConfirmarPgto)
            _buildAcoes(t, precisaAvaliar, podeConfirmarPgto, isLojista),
        ],
      ),
    );
  }

  Widget _buildEsperandoOutraParte(Turno t, bool isLojista) {
    final texto = isLojista
        ? 'Você confirmou. Aguardando o motoboy confirmar o recebimento.'
        : 'Você confirmou. Aguardando o lojista confirmar o pagamento.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.teal.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top_rounded,
                size: 14, color: AppColors.tealDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texto,
                  style: tsJakarta(11.5, FontWeight.w600,
                      color: AppColors.tealDeep, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcoes(
      Turno t, bool podeAvaliar, bool podePagar, bool isLojista) {
    final labelPgto = isLojista
        ? 'Confirmar pagamento'
        : 'Confirmar recebimento';
    final iconPgto = isLojista
        ? Icons.payments_rounded
        : Icons.check_circle_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          if (podeAvaliar) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => _abrirAvaliacao(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.amberSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.amber.withOpacity(0.4),
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_outline_rounded,
                          size: 14, color: AppColors.onTertiaryContainer),
                      const SizedBox(width: 6),
                      Text('Avaliar',
                          style: tsJakarta(12, FontWeight.w700,
                              color: AppColors.onTertiaryContainer)),
                    ],
                  ),
                ),
              ),
            ),
            if (podePagar) const SizedBox(width: 8),
          ],
          if (podePagar)
            Expanded(
              child: GestureDetector(
                onTap: () => (isLojista && t.multiVaga)
                    ? _abrirInscritosPagamento(t)
                    : _confirmarPagamento(t, isLojista: isLojista),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconPgto,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(labelPgto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tsJakarta(12, FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
