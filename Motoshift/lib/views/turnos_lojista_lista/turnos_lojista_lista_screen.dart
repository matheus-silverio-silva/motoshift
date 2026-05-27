import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';

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

  void _onNav(int i) {
    switch (i) {
      case 0:
        Navigator.pushReplacementNamed(
            context, AppRoutes.dashboardLojista);
      case 1:
        Navigator.pushReplacementNamed(context, AppRoutes.agenda);
      case 2:
        break;
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.perfil);
    }
  }

  List<Turno> _turnosFiltrados(List<Turno> todos) {
    if (_filtro == 'abertos') {
      return todos
          .where((t) =>
              t.status == StatusTurno.aberto ||
              t.status == StatusTurno.aceito)
          .toList();
    }
    if (_filtro == 'finalizados') {
      return todos
          .where((t) => t.status == StatusTurno.finalizado)
          .toList();
    }
    return todos;
  }

  PillVariant _pillFor(StatusTurno s) => switch (s) {
        StatusTurno.aceito => PillVariant.teal,
        StatusTurno.emAndamento => PillVariant.amber,
        StatusTurno.finalizado => PillVariant.good,
        _ => PillVariant.ghost,
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nome = auth.usuario?.nome.split(' ').first ?? 'Lojista';
    final initials = nome.length >= 2
        ? nome.substring(0, 2).toUpperCase()
        : nome.toUpperCase();

    return AppScaffold(
      header: AppHeader.greeting(
        greeting: 'Seus turnos',
        name: nome,
        avatarInitials: initials,
      ),
      bottomNav: AppBottomNav(
        userType: UserType.lojista,
        currentIndex: 2,
        onTap: _onNav,
      ),
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
                            name: t.titulo,
                            meta: [
                              t.horarioFormatado,
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

  Widget _buildFiltros() {
    const opcoes = [
      ('todos', 'Todos'),
      ('abertos', 'Abertos'),
      ('finalizados', 'Finalizados'),
    ];

    return Row(
      children: opcoes.map((op) {
        final sel = _filtro == op.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _filtro = op.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
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
            color: Color(0xFF3A2603), size: 18),
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.publicarTurno),
      ),
    );
  }
}
