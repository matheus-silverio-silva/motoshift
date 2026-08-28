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
import '../avaliacao/avaliacao_screen.dart';
import 'historico_conteudo_desktop.dart';
import 'historico_conteudo_mobile.dart';
import 'historico_resumo.dart';

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
  //
  // A tela cuida de buscar, guardar e agir. Os dois layouts vivem em
  // historico_conteudo_mobile.dart e historico_conteudo_desktop.dart, e as
  // regras em historico_resumo.dart — antes tudo isso era um State só, de
  // 1.127 linhas.

  @override
  Widget build(BuildContext context) {
    final isLojista =
        context.watch<AuthService>().usuario?.tipo == TipoUsuario.lojista;
    final resumo =
        HistoricoResumo(turnos: _turnos, avaliados: _turnosAvaliados);

    return AdaptiveScaffold(
      header: AppHeader.back(title: 'Histórico de turnos'),
      desktopTitle: 'Histórico de turnos',
      desktopSubtitle: _subtituloDesktop(resumo),
      // Também é sub-página do Perfil, e /historico-turnos não é item de
      // sidebar: apontar para ele deixava o desktop sem nada destacado.
      desktopSelectedRoute: AppRoutes.perfil,
      desktopBody: _comEstado(
        HistoricoConteudoDesktop(
          resumo: resumo,
          filtro: _filtro,
          isLojista: isLojista,
          onFiltro: (f) => setState(() => _filtro = f),
          onAbrirTurno: (t) => _abrirTurno(t, isLojista),
        ),
      ),
      body: _comEstado(
        HistoricoConteudoMobile(
          resumo: resumo,
          filtro: _filtro,
          isLojista: isLojista,
          onFiltro: (f) => setState(() => _filtro = f),
          onRecarregar: _carregar,
          onAbrirTurno: (t) => _abrirTurno(t, isLojista),
          onAvaliar: _abrirAvaliacao,
          onPagar: (t) => (isLojista && t.multiVaga)
              ? _abrirInscritosPagamento(t)
              : _confirmarPagamento(t, isLojista: isLojista),
        ),
      ),
    );
  }

  /// Carregando e vazio são iguais nas duas larguras; só o conteúdo muda.
  Widget _comEstado(Widget conteudo) {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.teal),
      );
    }
    if (_turnos.isEmpty) return _buildVazio();
    return conteudo;
  }

  void _abrirTurno(Turno t, bool isLojista) {
    Navigator.pushNamed(
      context,
      isLojista ? AppRoutes.turnoLojista : AppRoutes.detalheTurno,
      arguments: t,
    );
  }

  String _subtituloDesktop(HistoricoResumo resumo) {
    if (_carregando) return 'Carregando histórico…';
    final n = resumo.total;
    if (n == 0) return 'Nenhum turno encerrado ainda';
    return '$n ${n == 1 ? 'turno' : 'turnos'} desde '
        '${DateFormat('MMMM \'de\' y', 'pt_BR').format(resumo.maisAntigo!)}';
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

}
