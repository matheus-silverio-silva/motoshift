import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/widgets/desktop/app_sidebar.dart';

import '../test_helpers.dart';

/// O menu da esquerda tem de ser o mapa completo do aplicativo, e o mesmo nas
/// duas larguras de tela.
///
/// Estes testes existem porque a versão anterior tinha cinco itens por papel e
/// deixava o resto — avaliações do lojista, histórico, notificações — só dentro
/// do Perfil. O primeiro teste é o que impede a regressão silenciosa: uma tela
/// nova que entre no app sem entrada no menu derruba a suíte aqui, e não seis
/// meses depois quando alguém reclamar que "não acha".
void main() {
  setUpAll(setupGoldenTests);

  /// Rotas que o menu NÃO deve listar, com o motivo.
  ///
  /// Duas famílias, e só duas: o que não é do aplicativo logado (login,
  /// cadastro, splash…) e o que precisa de um turno escolhido antes — não há
  /// como abrir "avaliar entregador" a partir de um menu sem dizer de qual
  /// turno.
  const foraDoMenu = <String>{
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.cadastro,
    AppRoutes.esqueceuSenha,
    // Precisam de argumento de rota.
    AppRoutes.detalheTurno,
    AppRoutes.turnoLojista,
    AppRoutes.avaliacao,
    AppRoutes.avaliarEntregadores,
    // Sub-páginas alcançadas de dentro de outra tela.
    AppRoutes.sacarPix,
    AppRoutes.dadosPessoais,
    AppRoutes.cnhVeiculo,
    // Legadas: apontam para as mesmas telas dos itens que já estão no menu.
    AppRoutes.meusTurnos,
    AppRoutes.agendarTurno,
  };

  /// Rotas exclusivas de um papel — não podem aparecer no menu do outro.
  const soDoLojista = <String>{
    AppRoutes.dashboardLojista,
    AppRoutes.turnosLojista,
    AppRoutes.publicarTurno,
    AppRoutes.saldoLojista,
  };
  const soDoMotoboy = <String>{
    AppRoutes.dashboardMotoboy,
    AppRoutes.turnosDisponiveis,
    AppRoutes.carteira,
  };

  List<String> rotasDe(List<SidebarSection> sections) =>
      [for (final s in sections) for (final i in s.items) i.route];

  test('toda rota do app logado está no menu de algum papel', () {
    final noMenu = {
      ...rotasDe(SidebarItems.lojista()),
      ...rotasDe(SidebarItems.motoboy()),
    };

    final esperadas = _todasAsRotas.difference(foraDoMenu);
    final ausentes = esperadas.difference(noMenu);

    expect(
      ausentes,
      isEmpty,
      reason: 'Rotas sem entrada no menu lateral: $ausentes. '
          'Acrescente o item em SidebarItems ou liste a rota em foraDoMenu '
          'com o motivo.',
    );
  });

  test('o menu de cada papel só oferece o que aquele papel pode abrir', () {
    final lojista = rotasDe(SidebarItems.lojista()).toSet();
    final motoboy = rotasDe(SidebarItems.motoboy()).toSet();

    expect(lojista.intersection(soDoMotoboy), isEmpty,
        reason: 'O menu do lojista oferece rota exclusiva do entregador.');
    expect(motoboy.intersection(soDoLojista), isEmpty,
        reason: 'O menu do entregador oferece rota exclusiva do lojista.');

    // E o que o papel precisa está lá.
    expect(lojista, containsAll(soDoLojista));
    expect(motoboy, containsAll(soDoMotoboy));
  });

  test('avaliações e notas fiscais estão no menu dos DOIS papéis', () {
    for (final sections in [SidebarItems.lojista(), SidebarItems.motoboy()]) {
      final rotas = rotasDe(sections);
      expect(rotas, contains(AppRoutes.minhasAvaliacoes));
      expect(rotas, contains(AppRoutes.notasFiscais));
    }
  });

  test('nenhum item aparece duas vezes no mesmo menu', () {
    for (final sections in [SidebarItems.lojista(), SidebarItems.motoboy()]) {
      final rotas = rotasDe(sections);
      expect(rotas.length, rotas.toSet().length,
          reason: 'Rota repetida no menu: $rotas');
    }
  });

  testWidgets('no celular, o botão do header abre o menu completo',
      (tester) async {
    await pumpGolden(
      tester,
      tipoUsuario: TipoUsuario.motoboy,
      child: const DashboardMotoboyScreen(),
    );

    // Fechado, o menu não está na tela.
    expect(find.text('Notas fiscais'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Abrir menu'));
    await tester.pumpAndSettle();

    // Aberto, traz os itens que antes só existiam dentro do Perfil.
    expect(find.text('Notas fiscais'), findsOneWidget);
    expect(find.text('Avaliações'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Notificações'), findsOneWidget);
  });
}

/// Todas as constantes de [AppRoutes], lidas uma a uma.
///
/// Não há reflexão em Dart compilado para web, então a lista é manual — e é
/// justamente por isso que o teste acima vale: quem acrescentar uma rota sem
/// acrescentá-la aqui não quebra nada, mas quem a acrescentar aqui sem pôr no
/// menu, sim. O primeiro caso é pego na revisão; o segundo, pelo CI.
const _todasAsRotas = <String>{
  AppRoutes.splash,
  AppRoutes.login,
  AppRoutes.cadastro,
  AppRoutes.esqueceuSenha,
  AppRoutes.dashboardMotoboy,
  AppRoutes.dashboardLojista,
  AppRoutes.publicarTurno,
  AppRoutes.turnoLojista,
  AppRoutes.turnosLojista,
  AppRoutes.turnosDisponiveis,
  AppRoutes.detalheTurno,
  AppRoutes.carteira,
  AppRoutes.agenda,
  AppRoutes.notasFiscais,
  AppRoutes.avaliacao,
  AppRoutes.perfil,
  AppRoutes.notificacoes,
  AppRoutes.saldoLojista,
  AppRoutes.avaliarEntregadores,
  AppRoutes.meusTurnos,
  AppRoutes.agendarTurno,
  AppRoutes.sacarPix,
  AppRoutes.dadosPessoais,
  AppRoutes.cnhVeiculo,
  AppRoutes.minhasAvaliacoes,
  AppRoutes.historicoTurnos,
};
