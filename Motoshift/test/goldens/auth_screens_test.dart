// Goldens das telas públicas (sem login) — login, cadastro e recuperação de
// senha — e da troca de senha de quem está logado.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/views/alterar_senha/alterar_senha_screen.dart';
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

  // A tela deixou de ser orientação e virou o fluxo e-mail → código → senha
  // nova (SCRUM-32). O golden é o do passo 1, sem argumento de rota — o caso
  // de quem chega por link direto, sem e-mail digitado.
  testWidgets('RecuperarSenhaScreen', (tester) async {
    await pumpGolden(tester, child: const RecuperarSenhaScreen());
    await expectLater(
      find.byType(RecuperarSenhaScreen),
      matchesGoldenFile('goldens/recuperar_senha_screen.png'),
    );
  });

  // "Alterar senha" não é tela pública (abre do Perfil, com sessão), mas mora
  // aqui com as outras telas de senha.
  testWidgets('AlterarSenhaScreen', (tester) async {
    await pumpGolden(tester, child: const AlterarSenhaScreen());
    await expectLater(
      find.byType(AlterarSenhaScreen),
      matchesGoldenFile('goldens/alterar_senha_screen.png'),
    );
  });
}
