import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/usuario.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Envolve telas que exigem autenticação.
///
/// Resolve três problemas:
///  1. Deep-link direto (ex.: abrir `/#/dashboard-lojista` na URL) não pode
///     exibir tela protegida sem sessão — restaura o token salvo antes de decidir.
///  2. Sem sessão válida → redireciona para /login.
///  3. Papel incorreto (lojista tentando abrir tela de motoboy, ou vice-versa)
///     → redireciona para o dashboard correto.
class AuthGuard extends StatefulWidget {
  const AuthGuard({
    required this.child,
    this.papel,
    super.key,
  });

  /// Tela protegida a ser exibida quando o acesso for permitido.
  final Widget child;

  /// Papel exigido. `null` = qualquer usuário autenticado (telas compartilhadas).
  final TipoUsuario? papel;

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  @override
  void initState() {
    super.initState();
    // Garante restauração de sessão em deep-link (quando a Splash foi pulada).
    final auth = context.read<AuthService>();
    if (!auth.inicializado) {
      WidgetsBinding.instance.addPostFrameCallback((_) => auth.inicializar());
    }
  }

  void _redirecionar(String rota) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, rota);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Ainda restaurando a sessão → tela de carregamento neutra.
    if (!auth.inicializado) {
      return const _GuardLoading();
    }

    // Não autenticado → login.
    if (!auth.autenticado) {
      _redirecionar(AppRoutes.login);
      return const _GuardLoading();
    }

    // Papel incorreto → manda para o dashboard do papel real.
    if (widget.papel != null && auth.usuario!.tipo != widget.papel) {
      final destino = auth.usuario!.tipo == TipoUsuario.motoboy
          ? AppRoutes.dashboardMotoboy
          : AppRoutes.dashboardLojista;
      _redirecionar(destino);
      return const _GuardLoading();
    }

    return widget.child;
  }
}

class _GuardLoading extends StatelessWidget {
  const _GuardLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      ),
    );
  }
}
