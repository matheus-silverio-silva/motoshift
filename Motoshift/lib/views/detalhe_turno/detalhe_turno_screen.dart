import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_selecionado_provider.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
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
      header: AppHeader.back(title: 'Detalhes do Turno'),
      body: turno == null
          ? const Center(child: Text('Turno não encontrado.'))
          : DetalheTurnoConteudo(
              turno: turno,
              onAceito: () => Navigator.pop(context, true),
            ),
    );
  }
}
