import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/app.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/routes/nav_config.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';

import '../test_helpers.dart';

/// O menu da esquerda tem de ser o mapa completo do aplicativo, e o mesmo nas
/// duas larguras de tela.
///
/// Estes testes existem porque a versão anterior tinha cinco itens por papel e
/// deixava o resto — avaliações do lojista, histórico, notificações — só dentro
/// do Perfil. O primeiro teste é o que impede a regressão silenciosa: uma tela
/// nova que entre no app sem entrada no menu derruba a suíte aqui, e não seis
/// meses depois quando alguém reclamar que "não acha".
///
/// <h3>A lista de rotas deixou de ser mantida à mão</h3>
/// Ela era uma constante neste arquivo, e o próprio comentário admitia a
/// fraqueza: "quem acrescentar uma rota sem acrescentá-la aqui não quebra
/// nada". Foi exatamente o que aconteceu — /extrato e /relatorio-financeiro
/// entraram no app com tela pronta e nenhum ponto de entrada, e este teste não
/// viu. Agora ele lê [rotasDoApp], o mesmo registro que o `MaterialApp` usa.
void main() {
  setUpAll(setupGoldenTests);

  /// Rotas que o menu NÃO deve listar, com o motivo.
  ///
  /// Duas famílias, e só duas: o que não é do aplicativo logado (login,
  /// cadastro, splash…) e o que precisa de um argumento — não há como abrir
  /// "avaliar entregador" a partir de um menu sem dizer de qual turno.
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
    AppRoutes.lancamento,
    // Sub-páginas alcançadas de dentro de outra tela — o NavConfig as mapeia
    // para a seção que as contém (ver NavConfig.secaoDe).
    AppRoutes.dadosPessoais,
    AppRoutes.cnhVeiculo,
    AppRoutes.extrato,
    AppRoutes.recarga,
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

  List<String> rotasDe(TipoUsuario papel) =>
      [for (final i in NavConfig.itens(papel)) i.route];

  test('toda rota do app logado está no menu de algum papel', () {
    final noMenu = {
      ...rotasDe(TipoUsuario.lojista),
      ...rotasDe(TipoUsuario.motoboy),
    };

    // A fonte é o registro real de rotas, não uma cópia mantida à mão.
    final esperadas = rotasDoApp().keys.toSet().difference(foraDoMenu);
    final ausentes = esperadas.difference(noMenu);

    expect(
      ausentes,
      isEmpty,
      reason: 'Rotas sem entrada no menu: $ausentes. '
          'Acrescente o item em NavConfig ou liste a rota em foraDoMenu '
          'com o motivo.',
    );
  });

  test('toda rota listada em foraDoMenu existe de verdade', () {
    // Sem isto, apagar uma rota e esquecer de tirá-la da lista de exceções
    // deixaria o primeiro teste mais frouxo sem ninguém perceber.
    final registradas = rotasDoApp().keys.toSet();
    expect(foraDoMenu.difference(registradas), isEmpty,
        reason: 'foraDoMenu lista rota que não existe mais.');
  });

  test('o menu de cada papel só oferece o que aquele papel pode abrir', () {
    final lojista = rotasDe(TipoUsuario.lojista).toSet();
    final motoboy = rotasDe(TipoUsuario.motoboy).toSet();

    expect(lojista.intersection(soDoMotoboy), isEmpty,
        reason: 'O menu do lojista oferece rota exclusiva do entregador.');
    expect(motoboy.intersection(soDoLojista), isEmpty,
        reason: 'O menu do entregador oferece rota exclusiva do lojista.');

    // E o que o papel precisa está lá.
    expect(lojista, containsAll(soDoLojista));
    expect(motoboy, containsAll(soDoMotoboy));
  });

  test('avaliações e notas fiscais estão no menu dos DOIS papéis', () {
    for (final papel in TipoUsuario.values) {
      final rotas = rotasDe(papel);
      expect(rotas, contains(AppRoutes.minhasAvaliacoes));
      expect(rotas, contains(AppRoutes.notasFiscais));
    }
  });

  test('nenhum item aparece duas vezes no mesmo menu', () {
    for (final papel in TipoUsuario.values) {
      final rotas = rotasDe(papel);
      expect(rotas.length, rotas.toSet().length,
          reason: 'Rota repetida no menu: $rotas');
    }
  });

  test('a barra inferior tem exatamente quatro itens, e todos são do menu', () {
    for (final papel in TipoUsuario.values) {
      final barra = NavConfig.barraInferior(papel);

      // Quatro é o limite do desenho: com cinco, o rótulo de 8px não cabe em
      // 390px de largura.
      expect(barra, hasLength(4),
          reason: 'A barra inferior de $papel não tem quatro itens.');

      // Um atalho que não está no menu seria um destino sem página de origem.
      expect(rotasDe(papel), containsAll([for (final i in barra) i.route]));
    }
  });

  test('a seção de uma sub-página é um item do menu do papel', () {
    // O destaque do menu deriva daqui; se a seção apontasse para uma rota que
    // não é item, a sub-página não destacaria nada — que era o caso do Saldo
    // (marcava "Carteira", item que só existe no menu do entregador).
    const subPaginas = {
      AppRoutes.extrato: TipoUsuario.motoboy,
      AppRoutes.dadosPessoais: TipoUsuario.motoboy,
      AppRoutes.cnhVeiculo: TipoUsuario.motoboy,
    };

    subPaginas.forEach((rota, papel) {
      final secao = NavConfig.secaoDe(rota);
      expect(secao, isNotNull, reason: '$rota não tem seção.');
      expect(rotasDe(papel), contains(secao),
          reason: 'A seção de $rota não é item do menu de $papel.');
    });
  });

  test('a seção de uma rota de seção é ela mesma', () {
    for (final papel in TipoUsuario.values) {
      for (final rota in rotasDe(papel)) {
        expect(NavConfig.secaoDe(rota), rota);
      }
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
