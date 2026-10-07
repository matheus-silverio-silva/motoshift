import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/usuario.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'faixa_do_servidor.dart';

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

    // Ainda restaurando a sessão → tela de carregamento. Se o servidor estiver
    // acordando (SCRUM-48), ela diz isso; se não responder, oferece tentar de
    // novo — é o caso de quem recarrega a página numa tela interna.
    if (!auth.inicializado) {
      return _GuardLoading(auth: auth);
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
  const _GuardLoading({this.auth});

  /// Presente só enquanto a sessão é restaurada — é quando há servidor a
  /// esperar. Nos redirecionamentos a tela é o indicador e nada mais.
  final AuthService? auth;

  @override
  Widget build(BuildContext context) {
    final auth = this.auth;
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (auth == null)
              const _Indicador()
            else ...[
              ListenableBuilder(
                listenable: auth.servidor,
                builder: (context, _) => auth.servidor.semResposta
                    ? const SizedBox(height: 24)
                    : const _Indicador(),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FaixaDoServidor(
                    servidor: auth.servidor,
                    aoTentarDeNovo: auth.inicializar,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
    );
  }
}
