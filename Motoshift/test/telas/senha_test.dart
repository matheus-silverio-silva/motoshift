import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/auth_api.dart';
import 'package:moto_shift/views/alterar_senha/alterar_senha_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/recuperar_senha/recuperar_senha_screen.dart';
import 'package:moto_shift/widgets/olho_da_senha.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// Trocar e recuperar a senha pelo app (SCRUM-32).
///
/// O backend é um fake que anota o que recebeu: o que estes testes prendem é
/// o que a TELA manda e o que ela faz com cada resposta — em especial as duas
/// que não podem virar "erro genérico": a senha atual errada (400, no campo)
/// e o código errado (400, de volta ao passo do código).
void main() {
  setUpAll(setupGoldenTests);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A chave fica ou no próprio TextFormField (e-mail, código) ou no
  // CampoDeSenha que o embrulha.
  Finder campo(String chave) {
    final comAChave = find.byKey(Key(chave));
    final dentro = find.descendant(
        of: comAChave, matching: find.byType(TextFormField));
    return dentro.evaluate().isNotEmpty ? dentro : comAChave;
  }

  Future<void> tocar(WidgetTester tester, String chave) async {
    await tester.ensureVisible(find.byKey(Key(chave)));
    await tester.tap(find.byKey(Key(chave)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Alterar senha', () {
    Future<_ApiDeSenha> montar(WidgetTester tester, {ApiException? erro}) async {
      final api = _ApiDeSenha(erroAoTrocar: erro);
      await pumpGolden(tester, child: const AlterarSenhaScreen(), apiFake: api);
      return api;
    }

    Future<void> preencher(WidgetTester tester,
        {String atual = 'senha123',
        String nova = 'outra456',
        String? confirmar}) async {
      await tester.enterText(campo('alterar-senha-atual'), atual);
      await tester.enterText(campo('alterar-senha-nova'), nova);
      await tester.enterText(
          campo('alterar-senha-confirmar'), confirmar ?? nova);
    }

    testWidgets('manda a senha atual e a nova, e avisa que trocou',
        (tester) async {
      final api = await montar(tester);

      await preencher(tester);
      await tocar(tester, 'alterar-senha-salvar');

      expect(api.senhas.trocas, [('senha123', 'outra456')]);
      expect(find.text('Senha alterada.'), findsOneWidget);
    });

    testWidgets('Enter no último campo também salva', (tester) async {
      final api = await montar(tester);

      await preencher(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(api.senhas.trocas, [('senha123', 'outra456')]);
    });

    testWidgets('senha atual errada aparece NO CAMPO, e some ao redigitar',
        (tester) async {
      final api = await montar(tester,
          erro: const ApiException(400, 'A senha atual não confere.'));

      await preencher(tester, atual: 'nao-e-esta1');
      await tocar(tester, 'alterar-senha-salvar');

      expect(api.senhas.trocas, [('nao-e-esta1', 'outra456')]);
      expect(find.text('A senha atual não confere.'), findsOneWidget);
      expect(find.text('Senha alterada.'), findsNothing);
      // A tela continua aberta, com o que foi digitado.
      expect(find.byType(AlterarSenhaScreen), findsOneWidget);

      await tester.enterText(campo('alterar-senha-atual'), 'senha123');
      await tester.pump();
      expect(find.text('A senha atual não confere.'), findsNothing);
    });

    testWidgets('outro erro (sem conexão) vira aviso, não erro de campo',
        (tester) async {
      await montar(tester,
          erro: const ApiException(0, 'Sem conexao com o servidor'));

      await preencher(tester);
      await tocar(tester, 'alterar-senha-salvar');

      expect(find.text('Sem conexao com o servidor'), findsOneWidget);
      expect(find.byType(AlterarSenhaScreen), findsOneWidget);
    });

    testWidgets('não chama o backend com o formulário inválido',
        (tester) async {
      final api = await montar(tester);

      // Vazio.
      await tocar(tester, 'alterar-senha-salvar');
      expect(find.text('Informe a senha atual'), findsOneWidget);

      // Curta.
      await preencher(tester, nova: 'a1');
      await tocar(tester, 'alterar-senha-salvar');
      expect(find.text('Mínimo 6 caracteres'), findsOneWidget);

      // Confirmação diferente.
      await preencher(tester, confirmar: 'outra457');
      await tocar(tester, 'alterar-senha-salvar');
      expect(find.text('As senhas não conferem'), findsOneWidget);

      // Igual à atual.
      await preencher(tester, nova: 'senha123');
      await tocar(tester, 'alterar-senha-salvar');
      expect(find.text('A senha nova precisa ser diferente da atual'),
          findsOneWidget);

      expect(api.senhas.trocas, isEmpty);
    });

    testWidgets('as três senhas nascem ocultas, cada uma com o seu olho',
        (tester) async {
      await montar(tester);

      expect(find.byType(OlhoDaSenha), findsNWidgets(3));
      for (final chave in [
        'alterar-senha-atual',
        'alterar-senha-nova',
        'alterar-senha-confirmar',
      ]) {
        final field = tester.widget<TextField>(find.descendant(
            of: find.byKey(Key(chave)), matching: find.byType(TextField)));
        expect(field.obscureText, isTrue, reason: chave);
      }

      await tester.tap(find.descendant(
          of: find.byKey(const Key('alterar-senha-nova')),
          matching: find.byType(OlhoDaSenha)));
      await tester.pump();

      TextField f(String chave) => tester.widget<TextField>(find.descendant(
          of: find.byKey(Key(chave)), matching: find.byType(TextField)));
      expect(f('alterar-senha-nova').obscureText, isFalse);
      expect(f('alterar-senha-atual').obscureText, isTrue);
    });

    testWidgets('o Perfil tem a entrada "Alterar senha"', (tester) async {
      await pumpGolden(tester, child: PerfilScreen(agora: dataAncoraGolden));

      expect(find.byKey(const Key('perfil-alterar-senha')), findsOneWidget);
      expect(find.text('Alterar senha'), findsOneWidget);
    });
  });

  group('Recuperar senha', () {
    Future<_ApiDeSenha> montar(
      WidgetTester tester, {
      String? email,
      ApiException? erroAoRedefinir,
      ApiException? erroAoPedir,
    }) async {
      final api = _ApiDeSenha(
          erroAoRedefinir: erroAoRedefinir, erroAoPedir: erroAoPedir);
      await pumpGolden(
        tester,
        child: const RecuperarSenhaScreen(),
        apiFake: api,
        argumentos: email == null ? null : RecuperarSenhaArgs(email: email),
      );
      return api;
    }

    Future<void> ateOCodigo(WidgetTester tester,
        {String email = 'claudia@teste.com'}) async {
      await tester.enterText(campo('recuperar-email'), email);
      await tocar(tester, 'recuperar-enviar-codigo');
    }

    Future<void> ateASenha(WidgetTester tester,
        {String codigo = '123456'}) async {
      await ateOCodigo(tester);
      await tester.enterText(campo('recuperar-codigo'), codigo);
      await tocar(tester, 'recuperar-continuar');
    }

    testWidgets('passo 1: o e-mail do login já vem preenchido', (tester) async {
      await montar(tester, email: 'claudia@teste.com');

      expect(find.text('Passo 1 de 3'.toUpperCase()), findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(campo('recuperar-email'))
              .controller!
              .text,
          'claudia@teste.com');
    });

    testWidgets('passo 1: pede o código com o e-mail normalizado',
        (tester) async {
      final api = await montar(tester);

      await ateOCodigo(tester, email: '  Claudia@Teste.COM ');

      expect(api.senhas.pedidos, ['claudia@teste.com']);
      expect(find.text('PASSO 2 DE 3'), findsOneWidget);
      // Não diz que a conta existe: "se houver".
      expect(find.textContaining('Se houver uma conta com o e-mail '
          'claudia@teste.com'), findsOneWidget);
      // E diz onde o código está, porque o envio é simulado.
      expect(find.byKey(const Key('recuperar-aviso-simulado')), findsOneWidget);
    });

    testWidgets('passo 1: e-mail inválido não chama o backend', (tester) async {
      final api = await montar(tester);

      await ateOCodigo(tester, email: 'isto-nao-e-email');

      expect(api.senhas.pedidos, isEmpty);
      expect(find.text('E-mail inválido'), findsOneWidget);
      expect(find.text('PASSO 1 DE 3'), findsOneWidget);
    });

    testWidgets('passo 1: erro ao pedir (limite de requisições) fica no passo 1',
        (tester) async {
      await montar(tester,
          erroAoPedir: const ApiException(
              429, 'Muitas requisições. Tente de novo em alguns minutos.'));

      await ateOCodigo(tester);

      expect(find.text('Muitas requisições. Tente de novo em alguns minutos.'),
          findsOneWidget);
      expect(find.text('PASSO 1 DE 3'), findsOneWidget);
    });

    testWidgets('passo 2: só avança com 6 dígitos, e letras não entram',
        (tester) async {
      await montar(tester);
      await ateOCodigo(tester);

      await tester.enterText(campo('recuperar-codigo'), '12a34');
      await tocar(tester, 'recuperar-continuar');
      expect(find.text('O código tem 6 dígitos'), findsOneWidget);
      expect(find.text('PASSO 2 DE 3'), findsOneWidget);

      await tester.enterText(campo('recuperar-codigo'), '123456');
      await tocar(tester, 'recuperar-continuar');
      expect(find.text('PASSO 3 DE 3'), findsOneWidget);
    });

    testWidgets('passo 2: reenviar fica desligado por 1 minuto, depois pede outro código',
        (tester) async {
      final api = await montar(tester);
      await ateOCodigo(tester);

      TextButton reenviar() => tester
          .widget<TextButton>(find.byKey(const Key('recuperar-reenviar')));
      expect(reenviar().onPressed, isNull);
      expect(find.text('Reenviar código (aguarde 1 minuto)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
      expect(reenviar().onPressed, isNotNull);

      await tocar(tester, 'recuperar-reenviar');
      expect(api.senhas.pedidos, ['claudia@teste.com', 'claudia@teste.com']);
      // Pediu outro: o botão volta a esperar.
      expect(reenviar().onPressed, isNull);
    });

    testWidgets('passo 2: "Usar outro e-mail" volta ao passo 1', (tester) async {
      await montar(tester);
      await ateOCodigo(tester);

      await tocar(tester, 'recuperar-outro-email');

      expect(find.text('PASSO 1 DE 3'), findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(campo('recuperar-email'))
              .controller!
              .text,
          'claudia@teste.com');
    });

    testWidgets('passo 3: manda e-mail, código e senha nova, e volta ao login',
        (tester) async {
      final api = await montar(tester);
      await ateASenha(tester);

      await tester.enterText(campo('recuperar-senha-nova'), 'outra456');
      await tester.enterText(campo('recuperar-senha-confirmar'), 'outra456');
      await tocar(tester, 'recuperar-redefinir');

      expect(api.senhas.redefinicoes,
          [('claudia@teste.com', '123456', 'outra456')]);
      expect(find.text('Senha redefinida. Entre com a senha nova.'),
          findsOneWidget);
      // Saiu da tela (no teste não há pilha: vai para a rota do login). O
      // pump a mais é a transição de rota terminando.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RecuperarSenhaScreen), findsNothing);
    });

    testWidgets('passo 3: senha fraca ou confirmação diferente não chamam o backend',
        (tester) async {
      final api = await montar(tester);
      await ateASenha(tester);

      await tester.enterText(campo('recuperar-senha-nova'), 'abc');
      await tester.enterText(campo('recuperar-senha-confirmar'), 'abc');
      await tocar(tester, 'recuperar-redefinir');
      expect(find.text('Mínimo 6 caracteres'), findsOneWidget);

      await tester.enterText(campo('recuperar-senha-nova'), 'outra456');
      await tester.enterText(campo('recuperar-senha-confirmar'), 'outra457');
      await tocar(tester, 'recuperar-redefinir');
      expect(find.text('As senhas não conferem'), findsOneWidget);

      expect(api.senhas.redefinicoes, isEmpty);
    });

    testWidgets('código errado: volta ao passo 2 com a mensagem do backend, e a senha fica guardada',
        (tester) async {
      final api = await montar(tester,
          erroAoRedefinir: const ApiException(
              400, 'Código inválido ou expirado. Peça um novo código.'));
      await ateASenha(tester, codigo: '111111');

      await tester.enterText(campo('recuperar-senha-nova'), 'outra456');
      await tester.enterText(campo('recuperar-senha-confirmar'), 'outra456');
      await tocar(tester, 'recuperar-redefinir');

      expect(api.senhas.redefinicoes,
          [('claudia@teste.com', '111111', 'outra456')]);
      expect(find.text('PASSO 2 DE 3'), findsOneWidget);
      expect(find.text('Código inválido ou expirado. Peça um novo código.'),
          findsOneWidget);

      // Corrige o código: a mensagem some, e a senha não precisa ser redigitada.
      await tester.enterText(campo('recuperar-codigo'), '222222');
      await tester.pump();
      expect(find.text('Código inválido ou expirado. Peça um novo código.'),
          findsNothing);
      await tocar(tester, 'recuperar-continuar');
      expect(
          tester
              .widget<TextFormField>(campo('recuperar-senha-nova'))
              .controller!
              .text,
          'outra456');
    });

    testWidgets('a seta do cabeçalho volta um passo de cada vez',
        (tester) async {
      await montar(tester);
      await ateASenha(tester);
      expect(find.text('PASSO 3 DE 3'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Voltar'));
      await tester.pump();
      expect(find.text('PASSO 2 DE 3'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Voltar'));
      await tester.pump();
      expect(find.text('PASSO 1 DE 3'), findsOneWidget);
    });
  });
}

/// Anota o que chegaria ao backend e responde o que o teste mandar.
class _SenhasQueRegistram extends FakeAuthApi {
  _SenhasQueRegistram({this.erroAoTrocar, this.erroAoPedir, this.erroAoRedefinir});

  final ApiException? erroAoTrocar;
  final ApiException? erroAoPedir;
  final ApiException? erroAoRedefinir;

  final List<(String, String)> trocas = [];
  final List<String> pedidos = [];
  final List<(String, String, String)> redefinicoes = [];

  @override
  Future<void> trocarSenha({
    required String senhaAtual,
    required String senhaNova,
  }) async {
    trocas.add((senhaAtual, senhaNova));
    if (erroAoTrocar != null) throw erroAoTrocar!;
  }

  @override
  Future<void> esqueciSenha(String email) async {
    if (erroAoPedir != null) throw erroAoPedir!;
    pedidos.add(email);
  }

  @override
  Future<void> redefinirSenha({
    required String email,
    required String codigo,
    required String senhaNova,
  }) async {
    redefinicoes.add((email, codigo, senhaNova));
    if (erroAoRedefinir != null) throw erroAoRedefinir!;
  }
}

class _ApiDeSenha extends FakeApiService {
  _ApiDeSenha({
    ApiException? erroAoTrocar,
    ApiException? erroAoPedir,
    ApiException? erroAoRedefinir,
  }) : senhas = _SenhasQueRegistram(
          erroAoTrocar: erroAoTrocar,
          erroAoPedir: erroAoPedir,
          erroAoRedefinir: erroAoRedefinir,
        );

  final _SenhasQueRegistram senhas;

  @override
  AuthApi get auth => senhas;
}
