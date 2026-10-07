import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/auth_api.dart';
import 'package:moto_shift/utils/validators.dart';
import 'package:moto_shift/views/cadastro/cadastro_screen.dart';
import 'package:moto_shift/views/login/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// Login e cadastro pelo teclado (SCRUM-38) e com o e-mail normalizado
/// (SCRUM-28).
///
/// No web, quem digita e-mail e senha aperta Enter — e nada acontecia: os
/// campos não tinham ação nem `onFieldSubmitted`, e era preciso pegar o mouse
/// para clicar em "Entrar". No celular, o teclado mostrava "retorno" em vez de
/// "próximo"/"concluir".
void main() {
  setUpAll(setupGoldenTests);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder campo(String chave) => find.descendant(
      of: find.byKey(Key(chave)), matching: find.byType(TextFormField));

  TextField textField(WidgetTester tester, String chave) =>
      tester.widget<TextField>(find.descendant(
          of: find.byKey(Key(chave)), matching: find.byType(TextField)));

  group('login', () {
    testWidgets('Enter no campo de senha chama o login', (tester) async {
      final api = _ApiDeAuth();
      await pumpGolden(tester, child: const LoginScreen(), apiFake: api);

      await tester.enterText(campo('login-email'), 'claudia@teste.com');
      await tester.enterText(campo('login-senha'), 'senha123');
      // O Enter do teclado físico e o "Concluir" do celular chegam ao campo
      // como a ação do teclado.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(api.authFalsa.logins, [('claudia@teste.com', 'senha123')]);
    });

    testWidgets('o e-mail vai em minúsculas e sem espaço nas pontas',
        (tester) async {
      final api = _ApiDeAuth();
      await pumpGolden(tester, child: const LoginScreen(), apiFake: api);

      await tester.enterText(campo('login-email'), '  Claudia@Teste.COM ');
      await tester.enterText(campo('login-senha'), 'Senha123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // A senha vai como foi digitada: maiúscula em senha é senha.
      expect(api.authFalsa.logins, [('claudia@teste.com', 'Senha123')]);
    });

    testWidgets('Enter com o formulário inválido não chama o backend',
        (tester) async {
      final api = _ApiDeAuth();
      await pumpGolden(tester, child: const LoginScreen(), apiFake: api);

      await tester.enterText(campo('login-email'), 'isto-nao-e-email');
      await tester.enterText(campo('login-senha'), 'senha123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(api.authFalsa.logins, isEmpty);
      expect(find.text('E-mail inválido'), findsOneWidget);
    });

    testWidgets('não pergunta o perfil: quem diz se é loja ou entregador é a conta',
        (tester) async {
      await pumpGolden(tester, child: const LoginScreen());

      expect(find.text('Sou Lojista'), findsNothing);
      expect(find.text('Sou Motoboy'), findsNothing);
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('o e-mail é "próximo", a senha é "concluir", com as dicas de autofill',
        (tester) async {
      await pumpGolden(tester, child: const LoginScreen());

      final email = textField(tester, 'login-email');
      final senha = textField(tester, 'login-senha');
      expect(email.textInputAction, TextInputAction.next);
      expect(senha.textInputAction, TextInputAction.done);
      expect(email.autofillHints, contains(AutofillHints.email));
      expect(senha.autofillHints, [AutofillHints.password]);
      // Um formulário só para o gerenciador de senhas.
      expect(find.byType(AutofillGroup), findsOneWidget);
    });
  });

  test('o login manda só e-mail e senha — o perfil não vai, porque o backend não o usa',
      () async {
    final cliente = _ClienteQueGrava();

    await AuthApi(cliente).login(email: 'claudia@teste.com', senha: 'senha123');

    expect(cliente.caminho, '/auth/login');
    expect(cliente.corpo, {'email': 'claudia@teste.com', 'senha': 'senha123'});
  });

  group('cadastro', () {
    testWidgets('no cadastro a escolha de perfil continua, e lá ela vale', (tester) async {
      await pumpGolden(tester, child: const CadastroScreen());

      expect(find.text('Sou Lojista'), findsOneWidget);
      expect(find.text('Sou Motoboy'), findsOneWidget);
    });

    Future<void> preencher(WidgetTester tester, {required String email}) async {
      await tester.enterText(campo('cadastro-nome'), 'Maria Andrade');
      await tester.enterText(campo('cadastro-email'), email);
      await tester.enterText(campo('cadastro-telefone'), '41991234567');
      await tester.enterText(campo('cadastro-senha'), 'senha123');
      await tester.enterText(campo('cadastro-confirmar-senha'), 'senha123');
      // CNPJ válido (dígitos verificadores certos): a tela abre em "Sou Lojista".
      await tester.enterText(campo('cadastro-documento'), '11222333000181');
    }

    testWidgets('Enter no último campo envia o cadastro, com o e-mail normalizado',
        (tester) async {
      final api = _ApiDeAuth();
      await pumpGolden(tester, child: const CadastroScreen(), apiFake: api);

      await preencher(tester, email: ' MARIA@Exemplo.com ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(api.authFalsa.cadastros, ['maria@exemplo.com']);
    });

    testWidgets('só o último campo é "concluir"; os outros levam ao próximo',
        (tester) async {
      await pumpGolden(tester, child: const CadastroScreen());

      for (final chave in [
        'cadastro-nome',
        'cadastro-email',
        'cadastro-telefone',
        'cadastro-senha',
        'cadastro-confirmar-senha',
      ]) {
        expect(textField(tester, chave).textInputAction, TextInputAction.next,
            reason: chave);
      }
      expect(textField(tester, 'cadastro-documento').textInputAction,
          TextInputAction.done);
    });

    testWidgets('cada campo diz ao autofill o que é', (tester) async {
      await pumpGolden(tester, child: const CadastroScreen());

      expect(textField(tester, 'cadastro-nome').autofillHints,
          [AutofillHints.name]);
      expect(textField(tester, 'cadastro-email').autofillHints,
          contains(AutofillHints.email));
      expect(textField(tester, 'cadastro-telefone').autofillHints,
          [AutofillHints.telephoneNumber]);
      // newPassword: o gerenciador sugere senha nova em vez de preencher uma
      // que já existe.
      expect(textField(tester, 'cadastro-senha').autofillHints,
          [AutofillHints.newPassword]);
      expect(textField(tester, 'cadastro-confirmar-senha').autofillHints,
          [AutofillHints.newPassword]);
      expect(find.byType(AutofillGroup), findsOneWidget);
    });
  });

  test('normalizarEmail: sem espaço nas pontas, em minúsculas', () {
    expect(Validators.normalizarEmail('  Claudia@Teste.COM '), 'claudia@teste.com');
    expect(Validators.normalizarEmail('ja@normal.com'), 'ja@normal.com');
  });
}

/// O transporte que só anota o POST e devolve uma sessão qualquer.
class _ClienteQueGrava extends ApiClient {
  String? caminho;
  Map<String, dynamic>? corpo;

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    caminho = path;
    corpo = body;
    return <String, dynamic>{'token': 'token-de-teste', 'usuario': <String, dynamic>{}};
  }
}

/// Registra o que chegaria ao backend e recusa — assim o teste não precisa de
/// navegação nem de sessão: o que interessa é a chamada.
class _AuthQueRegistra extends FakeAuthApi {
  final List<(String, String)> logins = [];
  final List<String> cadastros = [];

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String senha,
  }) async {
    logins.add((email, senha));
    throw const ApiException(401, 'Credenciais inválidas.');
  }

  @override
  Future<Map<String, dynamic>> registrar(Usuario usuario, String senha) async {
    cadastros.add(usuario.email);
    throw const ApiException(409, 'E-mail já cadastrado');
  }
}

class _ApiDeAuth extends FakeApiService {
  final _AuthQueRegistra authFalsa = _AuthQueRegistra();

  @override
  AuthApi get auth => authFalsa;
}
