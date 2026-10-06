import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/presentation/providers/notificacao_provider.dart';
import 'package:moto_shift/services/api/notificacao_api.dart';

import '../test_helpers.dart';

/// O sino se atualiza sozinho (SCRUM-33).
///
/// A contagem só era buscada quando um painel abria: o lojista ficava com a
/// tela aberta e não via "Ricardo chegou às 14:03" até trocar de tela. Com
/// sessão, o provider passa a buscá-la a cada 45 s — parando em segundo plano
/// e no logout.
///
/// `testWidgets` e não `test`, mesmo sem widget nenhum: é ele que dá o relógio
/// falso (os 45 s passam com `tester.pump`) e que **falha se sobrar timer
/// pendente** no fim — que é a prova de que o relógio foi cancelado. Por isso
/// cada teste descarta o provider no fim do corpo, e não num tearDown: a
/// conferência dos timers roda antes dos tearDowns.
void main() {
  const quarentaECinco = Duration(seconds: 45);

  testWidgets('com sessão: busca na hora e depois a cada 45 s', (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);

    provider.acompanharSessao(7);
    await tester.pump();
    expect(api.contagens.buscas, [7]);
    expect(provider.naoLidas, 3);

    api.contagens.naoLidas = 5;
    await tester.pump(quarentaECinco);
    expect(api.contagens.buscas, [7, 7]);
    expect(provider.naoLidas, 5, reason: 'o sino mudou sem ninguém abrir tela');

    await tester.pump(quarentaECinco);
    await tester.pump(quarentaECinco);
    expect(api.contagens.buscas.length, 4);
    provider.dispose();
  });

  testWidgets('sem sessão não há relógio nenhum', (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);

    await tester.pump(const Duration(minutes: 5));

    expect(api.contagens.buscas, isEmpty);
    expect(provider.acompanhando, isFalse);
    provider.dispose();
  });

  testWidgets('logout cancela o relógio e zera o sino', (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);
    provider.acompanharSessao(7);
    await tester.pump();
    expect(provider.naoLidas, 3);

    provider.acompanharSessao(null);
    await tester.pump();

    expect(provider.acompanhando, isFalse);
    // O que era da conta anterior não fica no sino da próxima.
    expect(provider.naoLidas, 0);
    await tester.pump(const Duration(minutes: 5));
    expect(api.contagens.buscas, [7], reason: 'nenhuma busca depois do logout');
    provider.dispose();
  });

  testWidgets('outra conta entra: o relógio passa a perguntar por ela',
      (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);
    provider.acompanharSessao(7);
    await tester.pump();

    provider.acompanharSessao(9);
    await tester.pump();
    await tester.pump(quarentaECinco);

    expect(api.contagens.buscas, [7, 9, 9]);
    provider.dispose();
  });

  testWidgets('repetir a mesma sessão não reinicia nem busca de novo',
      (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);
    provider.acompanharSessao(7);
    await tester.pump();

    // É o que o app.dart faz a cada notifyListeners do AuthService.
    provider.acompanharSessao(7);
    provider.acompanharSessao(7);
    await tester.pump();

    expect(api.contagens.buscas, [7]);
    provider.dispose();
  });

  testWidgets('em segundo plano o relógio para; ao voltar, busca na hora e retoma',
      (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);
    // O estado do ciclo de vida é do binding, e sobrevive ao teste.
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    provider.acompanharSessao(7);
    await tester.pump();
    expect(api.contagens.buscas.length, 1);

    // O app foi para trás: ninguém está olhando o sino.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(provider.acompanhando, isFalse);
    await tester.pump(const Duration(minutes: 10));
    expect(api.contagens.buscas.length, 1, reason: 'nada em segundo plano');

    // Voltou: o que chegou nesse meio-tempo aparece sem esperar 45 s.
    api.contagens.naoLidas = 8;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.contagens.buscas.length, 2);
    expect(provider.naoLidas, 8);
    expect(provider.acompanhando, isTrue);

    await tester.pump(quarentaECinco);
    expect(api.contagens.buscas.length, 3);
    provider.dispose();
  });

  testWidgets('só perder o foco (inactive) não para o sino', (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    provider.acompanharSessao(7);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(quarentaECinco);

    expect(api.contagens.buscas.length, 2);
    provider.dispose();
  });

  testWidgets('intervalo nulo: busca ao entrar e não cria relógio',
      (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api, intervaloDaContagem: null);

    provider.acompanharSessao(7);
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));

    expect(api.contagens.buscas, [7]);
    expect(provider.acompanhando, isFalse);
    provider.dispose();
  });

  testWidgets('o intervalo é o do construtor', (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api,
        intervaloDaContagem: const Duration(seconds: 10));

    provider.acompanharSessao(7);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));

    expect(api.contagens.buscas.length, 4);
    provider.dispose();
  });

  testWidgets('resposta que chega depois do logout não ressuscita o sino',
      (tester) async {
    final api = _ApiQueConta()..contagens.atraso = const Duration(seconds: 2);
    final provider = NotificacaoProvider(api);

    provider.acompanharSessao(7);
    // A busca saiu e ainda não voltou quando a pessoa saiu da conta.
    provider.acompanharSessao(null);
    await tester.pump(const Duration(seconds: 3));

    expect(provider.naoLidas, 0);
    provider.dispose();
  });

  testWidgets('dispose cancela o relógio', (tester) async {
    final api = _ApiQueConta();
    final provider = NotificacaoProvider(api);
    provider.acompanharSessao(7);
    await tester.pump();

    provider.dispose();

    // Se o timer continuasse vivo, o testWidgets falharia aqui com
    // "A Timer is still pending".
    await tester.pump(const Duration(minutes: 5));
    expect(api.contagens.buscas, [7]);
  });
}

/// Conta as buscas e devolve o número que o teste mandar.
class _ContagemFalsa extends FakeNotificacaoApi {
  final List<int> buscas = [];
  int naoLidas = 3;
  Duration? atraso;

  @override
  Future<int> contarNotificacoesNaoLidas(int usuarioId) async {
    buscas.add(usuarioId);
    final resposta = naoLidas;
    if (atraso != null) await Future<void>.delayed(atraso!);
    return resposta;
  }
}

class _ApiQueConta extends FakeApiService {
  final _ContagemFalsa contagens = _ContagemFalsa();

  @override
  NotificacaoApi get notificacoes => contagens;
}
