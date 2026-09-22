// Goldens das telas públicas (sem login): login, cadastro e recuperação de
// senha.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/views/cadastro/cadastro_screen.dart';
import 'package:moto_shift/views/login/login_screen.dart';
import 'package:moto_shift/views/recuperar_senha/recuperar_senha_screen.dart';

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

  // O golden da SacarPixScreen saiu junto com a tela: era um stub "em breve"
  // enquanto a Carteira ja sacava de verdade, e o botao do inicio agora abre
  // a Carteira direto no dialogo de saque.

  // O stub "Em breve" virou tela de verdade: diz que a redefinição não é
  // automática, mostra o e-mail da conta e avisa do bloqueio por tentativas.
  // O golden é o da tela sem argumento de rota — o caso de quem chega por
  // link direto, sem e-mail digitado.
  testWidgets('RecuperarSenhaScreen', (tester) async {
    await pumpGolden(tester, child: const RecuperarSenhaScreen());
    await expectLater(
      find.byType(RecuperarSenhaScreen),
      matchesGoldenFile('goldens/recuperar_senha_screen.png'),
    );
  });
}
