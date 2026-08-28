import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'package:latlong2/latlong.dart';
import '../avaliacao/avaliacao_screen.dart';
import 'filtros_turnos_sheet.dart';
import 'turnos_conteudo_desktop.dart';
import '../../services/localizacao_service.dart';
import '../../widgets/mapa_raio.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_header.dart';
import '../../widgets/desktop/app_topbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_title.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';

class MeusTurnosScreen extends StatefulWidget {
  const MeusTurnosScreen({super.key, this.agora});

  /// Fixa o "agora" da saudação. Só os testes passam isto — ver
  /// [AgendaScreen.agora] para o porquê.
  final DateTime? agora;

  @override
  State<MeusTurnosScreen> createState() => _MeusTurnosScreenState();
}

class _MeusTurnosScreenState extends State<MeusTurnosScreen> {
  String? _fHorarioInicio;
  String? _fHorarioFim;
  int? _fDiaSemana;
  double? _fRaioMax;
  String _fOrdenarPor = 'valorAsc';

  // ── Filtro por raio (tela 18) ────────────────────────────────────────────
  double? _lat;
  double? _lng;
  double _raioKm = 8;
  bool _buscandoLocalizacao = false;

  /// Motivo de não ter localização. Fica visível na tela — sem posição a lista
  /// não é "vazia", ela é "não sei onde você está".
  FalhaLocalizacao? _falhaLocalizacao;

  bool get _porPerto => _lat != null && _lng != null;

  bool get _hasFilters =>
      _fHorarioInicio != null ||
      _fHorarioFim != null ||
      _fDiaSemana != null ||
      _fRaioMax != null ||
      _fOrdenarPor != 'valorAsc';

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

    provider.carregarMeusTurnos(id);
    _carregarDisponiveis();
  }

  Future<void> _carregarDisponiveis() async {
    final api = context.read<ApiService>();
    final provider = context.read<TurnoProvider>();

    if (_hasFilters || _porPerto) {
      try {
        final lista = await api.listarTurnosDisponiveisComFiltros(
          horarioInicio: _fHorarioInicio,
          horarioFim: _fHorarioFim,
          diaSemana: _fDiaSemana,
          raioMaxKm: _fRaioMax,
          // Com lat+lng+raioKm o backend filtra por distância real e devolve
          // distanciaKm em cada turno.
          lat: _lat,
          lng: _lng,
          raioKm: _porPerto ? _raioKm : null,
          ordenarPor: _porPerto
              ? 'distanciaAsc'
              : (_fOrdenarPor == 'valorAsc' ? null : _fOrdenarPor),
        );
        provider.setDisponiveisExterno(lista);
      } catch (_) {
        provider.carregarDisponiveis();
      }
    } else {
      provider.carregarDisponiveis();
    }
  }

  // ── Filtro por raio (tela 18) ────────────────────────────────────────────

  Future<void> _ativarPorPerto() async {
    setState(() {
      _buscandoLocalizacao = true;
      _falhaLocalizacao = null;
    });

    const servico = LocalizacaoService();
    final resultado = await servico.posicaoAtual();
    if (!mounted) return;

    setState(() {
      _buscandoLocalizacao = false;
      if (resultado.temPosicao) {
        _lat = resultado.latitude;
        _lng = resultado.longitude;
      } else {
        _falhaLocalizacao = resultado.falha;
      }
    });

    if (resultado.temPosicao) _carregarDisponiveis();
  }

  void _desativarPorPerto() {
    setState(() {
      _lat = null;
      _lng = null;
      _falhaLocalizacao = null;
    });
    _carregarDisponiveis();
  }

  String get _mensagemFalha => switch (_falhaLocalizacao) {
        FalhaLocalizacao.permissaoNegada =>
          'Sem permissão de localização, não dá para ordenar por distância. '
              'Você pode permitir e tentar de novo.',
        FalhaLocalizacao.permissaoNegadaParaSempre =>
          'A permissão de localização está bloqueada para o app. Libere nas '
              'configurações do sistema para filtrar por raio.',
        FalhaLocalizacao.servicoDesligado =>
          'A localização do aparelho está desligada. Ligue o GPS para filtrar '
              'por raio.',
        _ => 'Não foi possível obter sua localização agora.',
      };

  /// Faixa que aparece quando o usuário pediu "perto de mim" e não deu certo.
  /// Deixa explícito que a lista não está filtrada — em vez de mostrar um mapa
  /// vazio ou uma lista que parece filtrada e não está.
  Widget _buildFalhaLocalizacao() {
    final podeTentarDeNovo =
        _falhaLocalizacao == FalhaLocalizacao.permissaoNegada ||
            _falhaLocalizacao == FalhaLocalizacao.servicoDesligado ||
            _falhaLocalizacao == FalhaLocalizacao.erro;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.amber.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off_outlined,
              size: 20, color: AppColors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mostrando todos os turnos',
                  style: tsJakarta(12.5, FontWeight.w700,
                      color: AppColors.onTertiaryContainer),
                ),
                const SizedBox(height: 3),
                Text(
                  _mensagemFalha,
                  style: tsJakarta(11.5, FontWeight.w400,
                      color: AppColors.onTertiaryContainer, height: 1.4),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: podeTentarDeNovo
                      ? _ativarPorPerto
                      : () => const LocalizacaoService().abrirConfiguracoes(),
                  child: Text(
                    podeTentarDeNovo
                        ? 'Tentar novamente'
                        : 'Abrir configurações',
                    style: tsJakarta(12, FontWeight.w800,
                        color: AppColors.onTertiaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Controle de raio: liga/desliga o "perto de mim" e ajusta a distância.
  Widget _buildControleRaio() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _porPerto ? AppColors.teal : AppColors.line,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _porPerto
                    ? Icons.my_location_rounded
                    : Icons.location_searching_rounded,
                size: 18,
                color: _porPerto ? AppColors.teal : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _porPerto ? 'Perto de mim' : 'Filtrar por distância',
                  style: tsJakarta(12.5, FontWeight.w700,
                      color: _porPerto ? AppColors.tealDeep : AppColors.text),
                ),
              ),
              if (_buscandoLocalizacao)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.teal),
                )
              else
                Switch(
                  value: _porPerto,
                  activeColor: AppColors.teal,
                  onChanged: (v) =>
                      v ? _ativarPorPerto() : _desativarPorPerto(),
                ),
            ],
          ),
          if (_porPerto) ...[
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.teal,
                      inactiveTrackColor: AppColors.surface3,
                      thumbColor: AppColors.teal,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _raioKm,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      onChanged: (v) => setState(() => _raioKm = v),
                      onChangeEnd: (_) => _carregarDisponiveis(),
                    ),
                  ),
                ),
                Text('${_raioKm.toStringAsFixed(0)} km',
                    style: tsJakarta(12, FontWeight.w700,
                        color: AppColors.teal)),
              ],
            ),
            const SizedBox(height: 4),
            MapaRaio(
              centro: LatLng(_lat!, _lng!),
              raioKm: _raioKm,
              height: 150,
            ),
          ],
        ],
      ),
    );
  }

  void _limparFiltros() {
    setState(() {
      _fHorarioInicio = null;
      _fHorarioFim = null;
      _fDiaSemana = null;
      _fRaioMax = null;
      _fOrdenarPor = 'valorAsc';
    });
    _carregarDisponiveis();
  }

  String _greeting() {
    final h = (widget.agora ?? DateTime.now()).hour;
    if (h < 12) return 'Bom dia,';
    if (h < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  void _onNav(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacementNamed(context, AppRoutes.dashboardMotoboy);
      case 1:
        break;
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.carteira);
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Motoboy';
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AdaptiveScaffold(
      header: AppHeader.greeting(
        greeting: _greeting(),
        name: nome,
        avatarInitials: initials,
      ),
      bottomNav: AppBottomNav(
        userType: UserType.motoboy,
        currentIndex: 1,
        onTap: _onNav,
      ),
      body: Consumer<TurnoProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _buildControleRaio(),
              if (_falhaLocalizacao != null) ...[
                const SizedBox(height: 12),
                _buildFalhaLocalizacao(),
              ],
              const SizedBox(height: 4),
              _buildDisponiveisSection(provider, auth),
              // Turnos em andamento
              if (!provider.carregando) ...[
                const SizedBox(height: 8),
                _buildMeusTurnosSection(provider),
              ],
            ],
          );
        },
      ),
      desktopTitle: 'Turnos disponíveis',
      // O `watch` só é registrado quando o subtítulo vai mesmo ser usado. Se
      // ficasse solto aqui, o celular — que nem tem topbar — passaria a
      // rebuildar a tela inteira a cada notifyListeners() do provider.
      desktopSubtitle: context.isDesktop
          ? _subtituloDesktop(context.watch<TurnoProvider>())
          : null,
      desktopSelectedRoute: AppRoutes.turnosDisponiveis,
      desktopPrimaryAction: TopbarSecondaryButton(
        label: _hasFilters ? 'Filtros ativos' : 'Filtrar',
        icon: Icons.tune_rounded,
        onTap: _abrirFiltros,
      ),
      // O controle de raio e o aviso de localização são montados aqui porque
      // o estado de localização é da tela; o layout do desktop só os hospeda.
      desktopBody: TurnosConteudoDesktop(
        controleRaio: _buildControleRaio(),
        avisoLocalizacao:
            _falhaLocalizacao != null ? _buildFalhaLocalizacao() : null,
        porPerto: _porPerto,
        raioKm: _raioKm,
        hasFilters: _hasFilters,
        onAceito: _carregar,
      ),
    );
  }

  // ── Desktop — subtítulo da topbar ─────────────────────────────────────────

  String _subtituloDesktop(TurnoProvider provider) {
    if (provider.carregando) return 'Carregando turnos…';
    final n = provider.turnosDisponiveis.length;
    final base = n == 1 ? '1 turno aberto' : '$n turnos abertos';

    final aceitos = _turnosAceitos(provider).length;
    final partes = [
      base,
      if (aceitos > 0) '$aceitos ${aceitos == 1 ? 'aceito' : 'aceitos'}',
      if (_hasFilters) 'filtros ativos',
    ];
    return partes.join(' · ');
  }

  /// Turnos que o motoboy já aceitou e ainda vão acontecer (ou estão
  /// acontecendo) — a mesma seleção que o mobile mostra em "Meus turnos".
  List<Turno> _turnosAceitos(TurnoProvider provider) =>
      provider.meusTurnos.proximos();


  Widget _buildDisponiveisSection(
      TurnoProvider provider, AuthService auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionTitle(
                title: 'Turnos disponíveis',
                action: _hasFilters ? null : null,
              ),
            ),
            GestureDetector(
              onTap: _abrirFiltros,
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasFilters
                      ? AppColors.teal
                      : AppColors.surface3,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 14,
                        color: _hasFilters
                            ? Colors.white
                            : AppColors.muted),
                    const SizedBox(width: 4),
                    Text(
                      _hasFilters ? 'Ativos' : 'Filtrar',
                      style: tsJakarta(11, FontWeight.w700,
                          color: _hasFilters
                              ? Colors.white
                              : AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_hasFilters)
          GestureDetector(
            onTap: _limparFiltros,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded,
                      size: 13, color: AppColors.tealDeep),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Filtros ativos — toque para limpar',
                      style: tsJakarta(11, FontWeight.w600,
                          color: AppColors.tealDeep),
                    ),
                  ),
                  const Icon(Icons.close_rounded,
                      size: 13, color: AppColors.tealDeep),
                ],
              ),
            ),
          ),
        if (provider.carregando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.teal),
            ),
          )
        else if (provider.turnosDisponiveis.isEmpty)
          EmptyState(
            icon: _hasFilters || _porPerto
                ? Icons.filter_alt_off_outlined
                : Icons.two_wheeler_outlined,
            titulo: _hasFilters || _porPerto
                ? 'Nenhum turno encontrado'
                : 'Nenhum turno disponível',
            subtitulo: _porPerto
                ? 'Aumente o raio ou desligue o filtro por distância.'
                : _hasFilters
                    ? 'Tente afrouxar os filtros para ver mais turnos.'
                    : 'Assim que um lojista publicar, ele aparece aqui.',
          )
        else
          ...provider.turnosDisponiveis
              .take(8)
              .map((t) => _buildDisponivelCard(t, provider, auth)),
      ],
    );
  }

  Widget _buildDisponivelCard(
      Turno turno, TurnoProvider provider, AuthService auth) {
    return ShiftCard(
      horario: turno.horarioFormatado,
      name: turno.titulo,
      meta: [
        turno.regiao,
        // distanciaKm só vem quando a busca foi por raio; fora disso mostra o
        // raio de entrega do turno, como sempre mostrou.
        if (turno.distanciaKm != null)
          'a ${turno.distanciaKm!.toStringAsFixed(1).replaceAll('.', ',')} km'
        else
          '${turno.raioEntregaKm.toStringAsFixed(0)} km',
        if (turno.multiVaga)
          '${turno.vagasRestantes} de ${turno.vagas} vagas',
      ],
      value: 'R\$ ${turno.valorEstimado.toStringAsFixed(0)}',
      iconData: Icons.two_wheeler_outlined,
      // O chip "Ver" saiu: ele abria exatamente o que o toque no card já abre,
      // e com 24px de altura ficava abaixo do alvo mínimo de 44px. A pílula de
      // vagas ocupa o lugar e informa mais.
      pillLabel: turno.multiVaga
          ? '${turno.vagasRestantes} ${turno.vagasRestantes == 1 ? 'vaga' : 'vagas'}'
          : null,
      pillVariant: PillVariant.teal,
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.detalheTurno,
        arguments: turno,
      ),
    );
  }

  Widget _buildMeusTurnosSection(TurnoProvider provider) {
    final ativo = provider.meusTurnos
        .where((t) => t.status == StatusTurno.emAndamento)
        .firstOrNull;
    // Já filtrava por status, mas não por data nem ordem: turno aceito que
    // ficou para trás continuava listado como "próximo", e a ordem era a que
    // o backend devolvesse. O turno em andamento sai daqui porque tem seção
    // própria logo acima.
    final proximos = provider.meusTurnos
        .proximos()
        .where((t) => ativo == null || t.id != ativo.id)
        .toList();

    if (ativo == null && proximos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ativo != null) ...[
          SectionTitle(title: 'Turno em andamento'),
          _buildAtivoCard(ativo, provider),
        ],
        if (proximos.isNotEmpty) ...[
          SectionTitle(
            title: 'Próximos turnos',
            action: '${proximos.length} agendado(s)',
          ),
          ...proximos
              .take(3)
              .map((t) => ShiftCard(
                    horario: _formatProximoData(t.dataInicio, t.dataFim),
                    name: t.titulo,
                    meta: [t.regiao],
                    value:
                        'R\$ ${t.valorEstimado.toStringAsFixed(0)}',
                    iconData: Icons.schedule_outlined,
                    pillLabel: t.status.label,
                    pillVariant: t.status == StatusTurno.aceito
                        ? PillVariant.teal
                        : PillVariant.ghost,
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.detalheTurno,
                      arguments: t,
                    ),
                  )),
        ],
      ],
    );
  }

  Widget _buildAtivoCard(Turno turno, TurnoProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.tealSoft, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.two_wheeler_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(turno.titulo,
                        style: tsJakarta(13, FontWeight.w700,
                            color: AppColors.ink)),
                    Text(turno.horarioFormatado,
                        style: tsJakarta(10.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const StatusPill(
                  label: 'Em andamento',
                  variant: PillVariant.amber,
                  leadingDot: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final ok =
                        await provider.finalizarTurno(turno.id!);
                    if (!mounted) return;
                    if (ok) {
                      await _mostrarDialogAvaliacao(turno);
                      _carregar();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              provider.erro ?? 'Erro ao finalizar'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: Container(

                    constraints: const BoxConstraints(minHeight: 44),

                    alignment: Alignment.center,

                    padding:

                        const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'Confirmar conclusão',
                        style: tsJakarta(12, FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final ok =
                      await provider.cancelarTurno(turno.id!);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? 'Turno cancelado.'
                        : (provider.erro ?? 'Erro')),
                    backgroundColor:
                        ok ? Colors.orange : Colors.red,
                  ));
                  if (ok) _carregar();
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: Text(
                    'Cancelar',
                    style: tsJakarta(12, FontWeight.w700,
                        color: AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogAvaliacao(Turno turno) async {
    final auth = context.read<AuthService>();
    final motoboyId = auth.usuario?.id;
    if (motoboyId == null) return;

    await Navigator.pushNamed(
      context,
      AppRoutes.avaliacao,
      arguments: AvaliacaoArgs(
        turnoId: turno.id!,
        avaliadorId: motoboyId,
        avaliadoId: turno.lojistId,
        nomeAvaliado: turno.titulo,
      ),
    );
  }

  void _abrirFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FiltrosTurnosSheet(
        horarioInicio: _fHorarioInicio,
        horarioFim: _fHorarioFim,
        diaSemana: _fDiaSemana,
        raioMax: _fRaioMax,
        ordenarPor: _fOrdenarPor,
        onAplicar: (hi, hf, ds, raio, ord) {
          setState(() {
            _fHorarioInicio = hi;
            _fHorarioFim = hf;
            _fDiaSemana = ds;
            _fRaioMax = raio;
            _fOrdenarPor = ord;
          });
          _carregarDisponiveis();
        },
        onLimpar: _limparFiltros,
      ),
    );
  }

  String _formatProximoData(DateTime inicio, DateTime fim) {
    final agora = DateTime.now();
    final diff = inicio
        .difference(DateTime(agora.year, agora.month, agora.day));
    String dia;
    if (diff.inDays == 1) dia = 'Amanhã';
    else if (diff.inDays == 0) dia = 'Hoje';
    else {
      const semana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
      dia = semana[inicio.weekday % 7];
    }
    return '$dia, ${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')} – ${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}';
  }
}

