import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../presentation/providers/turno_selecionado_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/app_topbar.dart';
import '../../widgets/desktop/master_detail.dart';
import '../../widgets/desktop/shift_row.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';
import '../turno_lojista/turno_lojista_conteudo.dart';

class TurnosLojistaListaScreen extends StatefulWidget {
  const TurnosLojistaListaScreen({super.key});

  @override
  State<TurnosLojistaListaScreen> createState() =>
      _TurnosLojistaListaScreenState();
}

class _TurnosLojistaListaScreenState
    extends State<TurnosLojistaListaScreen> {
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final provider = context.read<TurnoProvider>();
    final id = auth.usuario?.id;
    if (id == null) return;
    if (provider.turnosLojista.isEmpty) {
      provider.carregarTurnosLojista(id);
    }
  }

  // O _onNav desta tela saiu: era um dos sete switches identicos de barra
  // inferior. Ver NavConfig — a tela agora informa so a secao em que esta.

  /// Abas da lista. "Expirados" existe porque o backend expira sozinho os
  /// turnos que ninguém aceitou até o horário de início (SCRUM-19): sem uma
  /// aba própria eles não estavam em "Abertos" nem em "Finalizados" e o
  /// lojista só os encontrava por acaso, em "Todos".
  ///
  /// "Cancelados" entrou pelo mesmo motivo, e o buraco era maior: o turno
  /// cancelado não tinha aba nenhuma, e "Abertos" olhava só para `aberto` e
  /// `aceito` — o turno **em andamento** também ficava de fora. Agora todo
  /// status cai em exatamente uma aba, que é o que [_filtroDe] diz e o que
  /// permite abrir um turno por link direto sem ele sumir da lista.
  static const List<(String, String)> _opcoesFiltro = [
    ('todos', 'Todos'),
    ('abertos', 'Abertos'),
    ('finalizados', 'Finalizados'),
    ('expirados', 'Expirados'),
    ('cancelados', 'Cancelados'),
  ];

  /// A aba onde um turno aparece — a inversa de [_turnosFiltrados].
  static String _filtroDe(StatusTurno status) => switch (status) {
        StatusTurno.aberto ||
        StatusTurno.aceito ||
        StatusTurno.emAndamento =>
          'abertos',
        StatusTurno.finalizado => 'finalizados',
        StatusTurno.expirado => 'expirados',
        StatusTurno.cancelado => 'cancelados',
      };

  List<Turno> _turnosFiltrados(List<Turno> todos) {
    if (_filtro == 'todos') return todos;
    return todos.where((t) => _filtroDe(t.status) == _filtro).toList();
  }

  /// Troca a aba e, se o turno selecionado não estiver na nova, desfaz a
  /// seleção. Sem isso o desktop ficava com o painel da direita mostrando um
  /// turno que não está em lugar nenhum da lista — e [_sincronizarAba]
  /// puxaria a aba de volta na sequência, brigando com o clique da pessoa.
  void _selecionarAba(String filtro) {
    if (_filtro == filtro) return;
    final selecao = context.read<TurnoSelecionadoProvider>();
    final turnos = context.read<TurnoProvider>().turnosLojista;
    setState(() => _filtro = filtro);
    if (!_turnosFiltrados(turnos).any((t) => t.id == selecao.id)) {
      selecao.limpar();
    }
  }

  /// Leva a aba até o turno que chegou de fora.
  ///
  /// `/turno-lojista` no desktop redireciona para esta lista com o turno já
  /// selecionado (notificação, dashboard, histórico). O filtro, porém,
  /// continuava sendo o que estava: quem abria um turno cancelado ou
  /// finalizado enquanto a aba era "Abertos" via a lista sem a linha
  /// correspondente e o painel da direita dizendo "Selecione um turno" —
  /// com um turno selecionado.
  void _sincronizarAba(Turno turno) {
    final destino = _filtroDe(turno.status);
    if (_filtro == destino) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _filtro != destino) setState(() => _filtro = destino);
    });
  }

  int _qtdExpirados(List<Turno> todos) =>
      todos.where((t) => t.status == StatusTurno.expirado).length;

  PillVariant _pillFor(StatusTurno s) => switch (s) {
        StatusTurno.aceito => PillVariant.teal,
        StatusTurno.emAndamento => PillVariant.amber,
        StatusTurno.finalizado => PillVariant.good,
        // Expirado e cancelado são fins de linha: pílula apagada, com o
        // rótulo dizendo qual dos dois foi.
        _ => PillVariant.ghost,
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Lojista';
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AdaptiveScaffold(
      header: AppHeader.greeting(
        greeting: 'Seus turnos',
        name: nome,
        avatarInitials: initials,
      ),
      desktopTitle: 'Turnos',
      // O `watch` só é registrado quando o subtítulo vai mesmo ser usado. Se
      // ficasse solto aqui, o celular — que nem tem topbar — passaria a
      // rebuildar a tela inteira a cada notifyListeners() do provider.
      desktopSubtitle: context.isDesktop
          ? _subtituloDesktop(context.watch<TurnoProvider>())
          : null,
      rotaDaSecao: AppRoutes.turnosLojista,
      desktopPrimaryAction: TopbarPrimaryButton(
        label: 'Publicar turno',
        icon: Icons.add,
        onTap: () => Navigator.pushNamed(context, AppRoutes.publicarTurno),
      ),
      desktopBody: _buildDesktop(),
      body: Consumer<TurnoProvider>(
        builder: (context, provider, _) {
          final filtrados = _turnosFiltrados(provider.turnosLojista);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    _buildFiltros(),
                    const SizedBox(height: 12),
                    if (provider.carregando)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.teal),
                        ),
                      )
                    else if (filtrados.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.line, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            'Nenhum turno publicado ainda.',
                            textAlign: TextAlign.center,
                            style: tsJakarta(13, FontWeight.w400,
                                color: AppColors.muted),
                          ),
                        ),
                      )
                    else
                      ...filtrados.map((t) => ShiftCard(
                            horario: t.horarioFormatado,
                            name: t.titulo,
                            meta: [
                              t.regiao,
                              '${t.raioEntregaKm.toStringAsFixed(0)} km',
                            ],
                            value:
                                'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                            iconData: Icons.store_outlined,
                            pillLabel: t.status.label,
                            pillVariant: _pillFor(t.status),
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.turnoLojista,
                              arguments: t,
                            ),
                          )),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          );
        },
      ),
    );
  }

  // ── Desktop — master-detail ───────────────────────────────────────────────

  String _subtituloDesktop(TurnoProvider provider) {
    if (provider.carregando) return 'Carregando turnos…';
    final todos = provider.turnosLojista;
    final ativos = todos.where((t) => t.status.ativo).length;
    final base = ativos == 1 ? '1 turno ativo' : '$ativos turnos ativos';

    // O expirado é o que o lojista mais precisa notar — ninguém aceitou o
    // turno a tempo. Vai no subtítulo para ele ver sem abrir a aba.
    final expirados = _qtdExpirados(todos);
    if (expirados == 0) return base;
    return '$base · $expirados '
        '${expirados == 1 ? 'expirado' : 'expirados'}';
  }

  Widget _buildDesktop() {
    return Consumer2<TurnoProvider, TurnoSelecionadoProvider>(
      builder: (context, provider, selecao, _) {
        final filtrados = _turnosFiltrados(provider.turnosLojista);

        // A seleção é resolvida contra a lista inteira, não contra a aba: o
        // turno pode ter chegado por link direto com um status que a aba
        // corrente não mostra. Resolvido o turno, _sincronizarAba leva a aba
        // até ele — e o detalhe já abre no mesmo quadro, sem piscar o
        // "Selecione um turno" enquanto a troca de aba não acontece.
        final doLojista = provider.turnosLojista
            .where((t) => t.id != null && t.id == selecao.id)
            .firstOrNull;
        if (doLojista != null) _sincronizarAba(doLojista);

        final selecionado = filtrados
                .where((t) => t.id != null && t.id == selecao.id)
                .firstOrNull ??
            doLojista;

        return MasterDetailLayout(
          listHeader: MasterDetailListHeader(
            titulo: provider.carregando
                ? 'Carregando…'
                : '${filtrados.length} '
                    '${filtrados.length == 1 ? 'turno' : 'turnos'}',
          ),
          // As pílulas saíram do `trailing` do cabeçalho quando a quinta aba
          // entrou: cinco não cabem nos 380px da coluna, e o Row do cabeçalho
          // espremeria a contagem até sumir antes de estourar. Como banda
          // própria elas rolam na horizontal, do mesmo jeito que no celular.
          list: Column(
            children: [
              _buildFiltrosDesktop(),
              Expanded(
                child: _buildListaDesktop(provider, filtrados, selecao),
              ),
            ],
          ),
          detail: selecionado == null
              ? const MasterDetailEmpty(
                  icon: Icons.local_shipping_outlined,
                  titulo: 'Selecione um turno',
                  subtitulo:
                      'Escolha um turno na lista ao lado para acompanhar o '
                      'andamento e o entregador designado.',
                )
              : TurnoLojistaConteudo(
                  key: ValueKey(selecionado.id),
                  turno: selecionado,
                  desktop: true,
                  onCancelado: () {
                    selecao.limpar();
                    _recarregar();
                  },
                ),
        );
      },
    );
  }

  Future<void> _recarregar() async {
    final auth = context.read<AuthService>();
    final id = auth.usuario?.id;
    if (id == null) return;
    context.read<TurnoProvider>().carregarTurnosLojista(id);
  }

  Widget _buildFiltrosDesktop() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _opcoesFiltro.map((op) {
            final sel = _filtro == op.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => _selecionarAba(op.$1),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    op.$2,
                    style: tsJakarta(11, FontWeight.w700,
                        color: sel ? Colors.white : AppColors.muted),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildListaDesktop(
    TurnoProvider provider,
    List<Turno> filtrados,
    TurnoSelecionadoProvider selecao,
  ) {
    if (provider.carregando) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.teal),
      );
    }
    if (filtrados.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _filtro == 'todos'
                ? 'Nenhum turno publicado ainda.'
                : 'Nenhum turno neste filtro.',
            textAlign: TextAlign.center,
            style: tsJakarta(12.5, FontWeight.w400, color: AppColors.muted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: filtrados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = filtrados[i];
        return ShiftRow(
          horario: t.horarioFormatado,
          valor: 'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
          meta: '${t.titulo} · ${t.regiao}',
          icon: t.status == StatusTurno.emAndamento
              ? Icons.schedule_outlined
              : Icons.storefront_outlined,
          amberIcon: t.status == StatusTurno.emAndamento,
          selected: t.id != null && t.id == selecao.id,
          pillLabel: t.status.label,
          pillVariant: _pillFor(t.status),
          onTap: () => selecao.selecionar(t.id),
        );
      },
    );
  }

  Widget _buildFiltros() {
    // Rolável na horizontal: com "Expirados" e "Cancelados" as cinco pílulas
    // passam da largura de um celular estreito.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _opcoesFiltro.map((op) {
          final sel = _filtro == op.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _selecionarAba(op.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                alignment: Alignment.center,
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
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border:
            Border(top: BorderSide(color: AppColors.line, width: 1.5)),
      ),
      child: AmberButton(
        label: 'Publicar novo turno',
        icon: const Icon(Icons.add_rounded,
            color: AppColors.onTertiary, size: 18),
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.publicarTurno),
      ),
    );
  }
}
