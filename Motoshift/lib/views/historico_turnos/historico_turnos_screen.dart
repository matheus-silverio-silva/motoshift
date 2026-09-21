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
          ? await api.turnos.listarTurnosLojista(id)
          : await api.turnos.listarMeusTurnos(id);
      final avaliados = await api.avaliacoes.buscarTurnosAvaliados(id);
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

  // _confirmarPagamento e _abrirInscritosPagamento sairam daqui.
  //
  // O primeiro abria um dialogo em que cada parte DECLARAVA que o dinheiro
  // tinha mudado de maos fora do app; o segundo era o painel do lojista para
  // fazer essa declaracao entregador por entregador, num turno multi-vaga. O
  // credito so acontecia quando as duas declaracoes existiam.
  //
  // Com a liquidacao automatica, finalizar o turno ja transfere o valor que o
  // lojista reservou ao publicar — nao ha o que declarar depois, e quem
  // trabalhou deixou de depender de um clique alheio para receber.

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
      // Marcava "Perfil" — heranca da epoca em que o Historico era uma
      // sub-pagina dele. Hoje e item proprio do menu.
      rotaDaSecao: AppRoutes.historicoTurnos,
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
