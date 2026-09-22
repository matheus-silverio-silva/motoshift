import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_selecionado_provider.dart';
import '../../routes/app_routes.dart';
import '../../routes/nav_config.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import 'detalhe_turno_conteudo.dart';

/// Rota `/detalhe-turno` — o detalhe empilhado do mobile.
///
/// Em tela larga esta rota deixa de existir: o detalhe vive no painel direito
/// da lista. Quem chegar aqui (link direto, ou a janela ter sido alargada com
/// a rota aberta) é levado para a lista com o turno já selecionado.
class DetalheTurnoScreen extends StatefulWidget {
  const DetalheTurnoScreen({super.key});

  @override
  State<DetalheTurnoScreen> createState() => _DetalheTurnoScreenState();
}

class _DetalheTurnoScreenState extends State<DetalheTurnoScreen> {
  bool _redirecionando = false;

  void _redirecionarParaLista(Turno? turno) {
    if (_redirecionando) return;
    _redirecionando = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (turno?.id != null) {
        context.read<TurnoSelecionadoProvider>().selecionar(turno!.id);
      }
      Navigator.pushReplacementNamed(context, AppRoutes.turnosDisponiveis);
    });
  }

  @override
  Widget build(BuildContext context) {
    final turno = ModalRoute.of(context)?.settings.arguments as Turno?;

    if (context.isDesktop) {
      _redirecionarParaLista(turno);
      return const Scaffold(
        backgroundColor: AppColors.surface2,
        body: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.teal),
        ),
      );
    }

    return AppScaffold(
      header: AppHeader.back(title: 'Detalhes do turno'),
      body: turno == null
          // Rota aberta sem turno (link quebrado, recarga da página no
          // navegador): antes era um Text solto no meio da tela e nenhuma
          // saída. Agora diz o que houve e oferece o caminho de volta.
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                titulo: 'Turno não encontrado',
                subtitulo: 'Este link não traz o turno que deveria abrir.',
                acaoLabel: 'Voltar',
                onAcao: () => Navigator.of(context).canPop()
                    ? Navigator.pop(context)
                    : NavConfig.voltarParaRaiz(
                        context, context.read<AuthService>().usuario?.tipo),
              ),
            )
          : DetalheTurnoConteudo(
              turno: turno,
              onMudou: () => Navigator.pop(context, true),
            ),
    );
  }
}
