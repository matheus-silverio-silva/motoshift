import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/turno.dart';
import '../../presentation/providers/turno_selecionado_provider.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';
import 'turno_lojista_conteudo.dart';

/// Rota `/turno-lojista` — o detalhe empilhado do mobile.
///
/// Em tela larga o detalhe vive no painel direito da lista de turnos do
/// lojista, então esta rota redireciona para lá com o turno já selecionado.
class TurnoLojistScreen extends StatefulWidget {
  const TurnoLojistScreen({super.key});

  @override
  State<TurnoLojistScreen> createState() => _TurnoLojistScreenState();
}

class _TurnoLojistScreenState extends State<TurnoLojistScreen> {
  bool _redirecionando = false;

  void _redirecionarParaLista(Turno? turno) {
    if (_redirecionando) return;
    _redirecionando = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (turno?.id != null) {
        context.read<TurnoSelecionadoProvider>().selecionar(turno!.id);
      }
      Navigator.pushReplacementNamed(context, AppRoutes.turnosLojista);
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
      header: AppHeader.back(title: 'Turno'),
      body: turno == null
          ? const Center(child: Text('Turno não encontrado.'))
          : TurnoLojistaConteudo(
              turno: turno,
              onCancelado: () => Navigator.pop(context, true),
            ),
    );
  }
}
