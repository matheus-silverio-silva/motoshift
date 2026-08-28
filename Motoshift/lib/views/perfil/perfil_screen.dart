import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/desktop/content_grid.dart';
import '../../widgets/menu_row.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key, this.agora});

  /// Fixa o "agora" do contador "X meses na plataforma". So os testes passam
  /// isto: o numero sobe todo dia 1o, e sem fixar o golden do perfil quebra
  /// sozinho na virada do mes.
  final DateTime? agora;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  /// Métricas do dashboard. O perfil não tem endpoint próprio, e
  /// `turnosFinalizados` já é calculado lá — reaproveita em vez de recontar.
  Map<String, dynamic>? _dash;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final usuario = auth.usuario;
    if (usuario?.id == null) return;

    try {
      final data = usuario!.tipo == TipoUsuario.lojista
          ? await api.dashboardLojista(usuario.id!)
          : await api.dashboardMotoboy(usuario.id!);
      if (mounted) setState(() => _dash = data);
    } catch (_) {
      // Estatística é informação secundária: falha vira "—", não erro de tela.
    }
  }

  Widget _buildStatsCard(Usuario? usuario) {
    final turnos = (_dash?['turnosFinalizados'] as num?)?.toInt();
    final avaliacao = usuario?.mediaAvaliacao;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          // "137" e "96%" eram literais com um TODO de integração. Turnos
          // agora vem do backend; pontualidade foi substituída pela avaliação
          // recebida, porque não existe registro de pontualidade no modelo —
          // calculá-la exigiria o horário real de início do turno, que a
          // plataforma ainda não guarda.
          _StatCell(value: turnos?.toString() ?? '—', label: 'TURNOS'),
          const _StatDivider(),
          _StatCell(
            value: avaliacao != null ? avaliacao.toStringAsFixed(1) : 'N/D',
            label: 'AVALIAÇÃO',
          ),
          const _StatDivider(),
          _StatCellDynamic(agora: widget.agora),
        ],
      ),
    );
  }

  static int _calcularMesesPlataforma(DateTime? criadoEm, DateTime? agoraInjetado) {
    if (criadoEm == null) return 0;
    final agora = agoraInjetado ?? clock.now();
    final meses = (agora.year - criadoEm.year) * 12 +
        (agora.month - criadoEm.month);
    return meses < 0 ? 0 : meses;
  }

  void _onNav(BuildContext context, int i, bool isLojista) {
    if (isLojista) {
      switch (i) {
        case 0:
          Navigator.pushReplacementNamed(
              context, AppRoutes.dashboardLojista);
        case 1:
          Navigator.pushReplacementNamed(context, AppRoutes.agenda);
        case 2:
          Navigator.pushReplacementNamed(
              context, AppRoutes.turnosLojista);
        case 3:
          break;
      }
    } else {
      switch (i) {
        case 0:
          Navigator.pushReplacementNamed(
              context, AppRoutes.dashboardMotoboy);
        case 1:
          Navigator.pushReplacementNamed(
              context, AppRoutes.turnosDisponiveis);
        case 2:
          Navigator.pushReplacementNamed(context, AppRoutes.carteira);
        case 3:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuario;
    final nome = usuario?.nome ?? 'Usuário';
    final isLojista = usuario?.tipo == TipoUsuario.lojista;
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AdaptiveScaffold(
      header: _PerfilHeader(
        nome: nome,
        initials: initials,
        tipo: isLojista ? 'Lojista' : 'Motoboy',
        score: usuario?.score,
      ),
      bottomNav: AppBottomNav(
        userType:
            isLojista ? UserType.lojista : UserType.motoboy,
        currentIndex: 3,
        onTap: (i) => _onNav(context, i, isLojista),
      ),
      desktopTitle: 'Perfil',
      desktopSubtitle: isLojista ? 'Conta de lojista' : 'Conta de entregador',
      desktopSelectedRoute: AppRoutes.perfil,
      desktopBody: _buildDesktop(context, usuario, isLojista, nome, initials),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
        children: [
          Transform.translate(
            offset: const Offset(0, -28),
            child: _buildStatsCard(usuario),
          ),
          const SizedBox(height: 4),
          ..._buildMenus(context, isLojista, nome),
        ],
      ),
    );
  }

  // ── Desktop — identidade à esquerda, menus à direita ─────────────────────

  Widget _buildDesktop(BuildContext context, Usuario? usuario, bool isLojista,
      String nome, String initials) {
    return ContentGrid(
      children: [
        GridCol(
          span: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: AppColors.headerGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0x29FFFFFF),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: const Color(0x38FFFFFF), width: 1.5),
                      ),
                      child: Center(
                        child: Text(initials,
                            style: tsBricolage(26, FontWeight.w800,
                                color: const Color(0xFFEAFFFD))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(nome,
                        textAlign: TextAlign.center,
                        style: tsBricolage(18, FontWeight.w800,
                            color: const Color(0xFFFFFFFF))),
                    const SizedBox(height: 4),
                    Text(
                      isLojista ? 'Lojista' : 'Motoboy',
                      style: tsJakarta(12, FontWeight.w600,
                          color: const Color(0xFFBFE5E3)),
                    ),
                    if (usuario?.email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        usuario!.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tsJakarta(11.5, FontWeight.w400,
                            color: const Color(0xFFBFE5E3)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildStatsCard(usuario),
            ],
          ),
        ),
        GridCol(
          span: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildMenus(context, isLojista, nome),
          ),
        ),
      ],
    );
  }

  /// Grupos de menu do perfil — os mesmos no mobile e no desktop.
  List<Widget> _buildMenus(
      BuildContext context, bool isLojista, String nome) {
    return [
          // CONTA
          MenuGroup(children: [
            MenuRow(
              icon: Icons.person_outline_rounded,
              label: 'Dados pessoais',
              subtitle: nome,
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.dadosPessoais),
            ),
            MenuRow(
              icon: isLojista
                  ? Icons.location_on_outlined
                  : Icons.two_wheeler_outlined,
              label: isLojista ? 'Endereço' : 'CNH e Veículo',
              subtitle: isLojista
                  ? 'Endereço comercial'
                  : 'Documentos do veículo',
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.cnhVeiculo),
            ),
          ]),
          const SizedBox(height: 14),
          // ATIVIDADE
          MenuGroup(children: [
            MenuRow(
              icon: Icons.star_outline_rounded,
              label: 'Minhas avaliações',
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.minhasAvaliacoes),
            ),
            MenuRow(
              icon: Icons.history_rounded,
              label: 'Histórico de turnos',
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.historicoTurnos),
            ),
          ]),
          const SizedBox(height: 14),
          // SAIR
          MenuGroup(children: [
            MenuRow(
              icon: Icons.logout_rounded,
              label: 'Sair da conta',
              danger: true,
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Sair',
                        style: tsBricolage(17, FontWeight.w800,
                            color: AppColors.ink)),
                    content: Text(
                      'Deseja realmente sair da sua conta?',
                      style: tsJakarta(13, FontWeight.w400,
                          color: AppColors.muted),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancelar',
                            style: tsJakarta(13, FontWeight.w600,
                                color: AppColors.muted)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Sair',
                            style: tsJakarta(13, FontWeight.w700,
                                color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  context.read<AuthService>().logout();
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.login,
                    (_) => false,
                  );
                }
              },
            ),
          ]),
    ];
  }
}

// ── Header especial com gradiente e avatar grande ─────────────────────────────
class _PerfilHeader extends StatelessWidget {
  const _PerfilHeader({
    required this.nome,
    required this.initials,
    required this.tipo,
    this.score,
  });

  final String nome;
  final String initials;
  final String tipo;
  final double? score;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          const BoxDecoration(gradient: AppColors.headerGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 44),
          child: Row(
            children: [
              // Avatar grande com badge verificado
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0x29FFFFFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0x38FFFFFF), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: tsBricolage(20, FontWeight.w800,
                            color: const Color(0xFFEAFFFD)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.good,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.tealDeep, width: 2.5),
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      style: tsBricolage(17, FontWeight.w800,
                          color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x29FFFFFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(tipo,
                              style: tsJakarta(9.5, FontWeight.w700,
                                  color: const Color(0xFFBFE5E3))),
                        ),
                        // Reputação, não avaliação. A estrela saiu daqui de
                        // propósito: estrela lê-se como "nota que me deram", e
                        // este número é o score da plataforma (começa em 5.0 e
                        // cai a cada cancelamento tardio). A avaliação recebida
                        // aparece no card de estatísticas, com estrela.
                        if (score != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.verified_user_rounded,
                              color: Color(0xFFBFE5E3), size: 12),
                          const SizedBox(width: 3),
                          Text(
                            '${score!.toStringAsFixed(1)} reputação',
                            style: tsJakarta(11, FontWeight.w700,
                                color: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stats card helpers ────────────────────────────────────────────────────────
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: tsBricolage(17, FontWeight.w800,
                    color: AppColors.ink)),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: tsJakarta(8.5, FontWeight.w700,
                  color: AppColors.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Stat cell que renderiza "X meses" baseado em criadoEm do AuthService.
class _StatCellDynamic extends StatelessWidget {
  const _StatCellDynamic({this.agora});

  final DateTime? agora;

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuario;
    final meses =
        _PerfilScreenState._calcularMesesPlataforma(usuario?.criadoEm, agora);
    final valor = meses == 0
        ? '< 1 mês'
        : meses == 1
            ? '1 mês'
            : '$meses meses';
    return _StatCell(value: valor, label: 'NA PLATAFORMA');
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: AppColors.line,
    );
  }
}
