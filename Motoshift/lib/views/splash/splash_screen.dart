import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

// ============================================================
// PRESENTATION — Splash / Session Restore (RF01)
// Verifica token salvo e redireciona para o dashboard correto.
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarSessao());
  }

  Future<void> _verificarSessao() async {
    final auth = context.read<AuthService>();
    await auth.inicializar();
    if (!mounted) return;

    if (auth.usuario != null) {
      final route = auth.usuario!.tipo == TipoUsuario.motoboy
          ? AppRoutes.dashboardMotoboy
          : AppRoutes.dashboardLojista;
      Navigator.pushReplacementNamed(context, route);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.teal,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.two_wheeler_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            // Tipografia do tema. Antes pedia `fontFamily: 'Manrope'`, que o
            // pubspec não declara em lugar nenhum — a primeira tela do app
            // caía na fonte padrão do sistema enquanto todo o resto usa
            // Bricolage + Jakarta.
            Text(
              'Moto Shift',
              style: tsBricolage(34, FontWeight.w800, color: Colors.white)
                  .copyWith(letterSpacing: -1.5),
            ),
            const SizedBox(height: 6),
            Text(
              'URBAN KINETIC',
              style: tsJakarta(12, FontWeight.w700,
                      color: Colors.white.withOpacity(0.55))
                  .copyWith(letterSpacing: 3),
            ),
            const SizedBox(height: 56),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
