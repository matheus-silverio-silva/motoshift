// Goldens das telas públicas (sem login): splash, login, cadastro
// e dos stubs simples (SacarPix, EsqueceuSenha).

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/views/cadastro/cadastro_screen.dart';
import 'package:moto_shift/views/login/login_screen.dart';
import 'package:moto_shift/views/stubs/stub_screens.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupGoldenTests();
  });

  // SplashScreen omitida: é tela de transição que faz pushReplacementNamed
  // imediatamente — a tela já não está mais em árvore no momento do snapshot.

  testWidgets('LoginScreen', (tester) async {
    await pumpGolden(tester, child: const LoginScreen());
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login_screen.png'),
    );
  });

  testWidgets('CadastroScreen', (tester) async {
    await pumpGolden(tester, child: const CadastroScreen());
    await expectLater(
      find.byType(CadastroScreen),
      matchesGoldenFile('goldens/cadastro_screen.png'),
    );
  });

  testWidgets('SacarPixScreen (stub)', (tester) async {
    await pumpGolden(tester, child: const SacarPixScreen());
    await expectLater(
      find.byType(SacarPixScreen),
      matchesGoldenFile('goldens/sacar_pix_screen.png'),
    );
  });

  testWidgets('EsqueceuSenhaScreen (stub)', (tester) async {
    await pumpGolden(tester, child: const EsqueceuSenhaScreen());
    await expectLater(
      find.byType(EsqueceuSenhaScreen),
      matchesGoldenFile('goldens/esqueceu_senha_screen.png'),
    );
  });
}
