import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/menu_row.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  Widget _buildStatsCard(Usuario? usuario) {
    // TODO: integrar turnosConcluidos, pontualidade e mesesNaPlataforma com backend
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      child: Row(
        children: [
          _StatCell(value: '137', label: 'TURNOS'),
          _StatDivider(),
          _StatCell(value: '96%', label: 'PONTUALIDADE'),
          _StatDivider(),
          _StatCell(value: '8 mês', label: 'NA PLATAFORMA'),
        ],
      ),
    );
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

    return AppScaffold(
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Transform.translate(
            offset: const Offset(0, -24),
            child: _buildStatsCard(usuario),
          ),
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
              icon: Icons.two_wheeler_outlined,
              label: 'CNH e Veículo',
              subtitle: isLojista ? null : 'Documentos do veículo',
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.cnhVeiculo),
            ),
            MenuRow(
              icon: Icons.notifications_outlined,
              label: 'Notificações',
              onTap: () => Navigator.pushNamed(
                  context, AppRoutes.notificacoes),
            ),
          ]),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
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
        ],
      ),
    );
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
                    ),
                    const SizedBox(height: 2),
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
                        if (score != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFF6A623), size: 12),
                          const SizedBox(width: 3),
                          Text(
                            score!.toStringAsFixed(1),
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
          Text(value,
              style: tsBricolage(16, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(label,
              style: tsJakarta(8.5, FontWeight.w700, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.line,
    );
  }
}
