import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/dre.dart';
import 'package:moto_shift/models/extrato_filtro.dart';
import 'package:moto_shift/models/lancamento_gerencial.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/financeiro_api.dart';
import 'package:moto_shift/utils/formato_fiscal.dart';
import 'package:moto_shift/views/resultado/lancamento_form.dart';
import 'package:moto_shift/views/resultado/resultado_screen.dart';
import 'package:moto_shift/widgets/situacao_do_resultado.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navegacao/app_de_teste.dart';
import '../test_helpers.dart';

/// A tela de resultado — a DRE dos dois papéis — e o formulário de lançamento
/// (RF13 / SCRUM-47).
///
/// O backend é um fake que devolve fixtures e anota o que a tela pediu: o que
/// estes testes prendem é o que a TELA mostra (a situação por extenso, e não
/// só por cor) e o que ela manda (o período, o lançamento, a exclusão).
void main() {
  setUpAll(setupGoldenTests);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A tela inteira construída de uma vez: num viewport alto a lista não
  /// deixa nada para depois, e o teste acha os painéis de baixo sem rolar.
  const alto = Size(390, 2600);

  /// No desktop os doze meses do gráfico cabem lado a lado; no celular a
  /// lista rola na horizontal e só constrói os que estão à vista.
  const desktopAlto = Size(1440, 1400);

  Future<FakeFinanceiroApi> montar(
    WidgetTester tester, {
    TipoUsuario papel = TipoUsuario.motoboy,
    bool comPrejuizo = false,
    bool semLancamentos = false,
    ApiException? erroAoSalvar,
    Size viewport = alto,
  }) async {
    final financeiro = FakeFinanceiroApi(
      papel: papel,
      comPrejuizo: comPrejuizo,
      semLancamentos: semLancamentos,
      erroAoSalvar: erroAoSalvar,
    );
    await pumpGolden(
      tester,
      child: ResultadoScreen(agora: dataAncoraGolden),
      tipoUsuario: papel,
      apiFake: _Api(papel, financeiro),
      viewport: viewport,
    );
    return financeiro;
  }

  Future<void> montarCom(
    WidgetTester tester,
    FakeFinanceiroApi financeiro, {
    TipoUsuario papel = TipoUsuario.motoboy,
  }) =>
      pumpGolden(
        tester,
        child: ResultadoScreen(agora: dataAncoraGolden),
        tipoUsuario: papel,
        apiFake: _Api(papel, financeiro),
        viewport: alto,
      );

  Future<void> tocar(WidgetTester tester, String chave) async {
    await tester.ensureVisible(find.byKey(Key(chave)));
    await tester.tap(find.byKey(Key(chave)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('a situação', () {
    testWidgets('lucro: a faixa diz "Lucro de R\$ ... no período", com o rótulo ao lado do ícone',
        (tester) async {
      await montar(tester);

      expect(find.text('Lucro de ${FormatoFiscal.moeda(111.95)} no período'), findsOneWidget);
      expect(find.byKey(const Key('resultado-situacao-rotulo')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('resultado-situacao-rotulo'))).data, 'Lucro');
      expect(find.text('01/08/2026 a 19/08/2026'), findsOneWidget);
      expect(find.textContaining('Prejuízo de'), findsNothing);
    });

    testWidgets('prejuízo: a faixa diz "Prejuízo de R\$ ... no período" — o valor sem sinal, a palavra dizendo',
        (tester) async {
      await montar(tester, comPrejuizo: true);

      expect(find.text('Prejuízo de ${FormatoFiscal.moeda(308.05)} no período'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('resultado-situacao-rotulo'))).data,
          'Prejuízo');
      expect(find.textContaining('Lucro de'), findsNothing);
    });

    testWidgets('o leitor de tela ouve a frase inteira, com o período', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, comPrejuizo: true);

      expect(
        find.bySemanticsLabel('Prejuízo de ${FormatoFiscal.moeda(308.05)} no período, '
            'de 01/08/2026 a 19/08/2026'),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets('sem nada informado, a tela avisa que o resultado só conhece a plataforma',
        (tester) async {
      await montar(tester, semLancamentos: true);

      expect(find.byKey(const Key('resultado-aviso-sem-lancamentos')), findsOneWidget);
      expect(find.textContaining('só conhece o que você recebeu pela plataforma'), findsOneWidget);
      expect(find.text('Nada informado neste período.'), findsOneWidget);
    });

    testWidgets('com lançamentos informados, o aviso não aparece', (tester) async {
      await montar(tester);
      expect(find.byKey(const Key('resultado-aviso-sem-lancamentos')), findsNothing);
    });
  });

  group('a demonstração', () {
    testWidgets('entregador: as linhas na ordem do backend, com "(−)", a origem e os subtotais',
        (tester) async {
      await montar(tester);

      for (final chave in [
        'pagamentos_recebidos', 'gorjetas_recebidas', 'receita_bruta',
        'das_mei', 'receita_liquida', 'combustivel', 'margem_de_contribuicao',
        'celular_internet', 'seguro', 'parcela_ou_aluguel_veiculo',
        'resultado',
      ]) {
        expect(find.byKey(Key('dre-$chave')), findsOneWidget, reason: chave);
      }
      Finder na(String chave, String texto) => find.descendant(
          of: find.byKey(Key('dre-$chave')), matching: find.text(texto));

      expect(na('combustivel', '(−) Combustível'), findsOneWidget);
      expect(na('combustivel', 'Informado por você'), findsOneWidget);
      expect(na('combustivel', FormatoFiscal.moeda(30)), findsOneWidget);
      expect(na('pagamentos_recebidos', 'Pagamentos de turnos'), findsOneWidget);
      expect(na('pagamentos_recebidos', 'Extrato'), findsOneWidget);
      expect(na('receita_bruta', '= Receita bruta'), findsOneWidget);
      expect(na('resultado', '= Resultado do período'), findsOneWidget);
      expect(na('resultado', FormatoFiscal.moeda(111.95)), findsOneWidget);
    });

    testWidgets(
        'linhas sem valor ficam de fora — a retenção só aparece se houver — e "Mostrar todas as linhas" as devolve',
        (tester) async {
      await montar(tester);
      const zeradas = ['retencoes_na_fonte', 'manutencao', 'outra_despesa_entregador'];

      for (final chave in zeradas) {
        expect(find.byKey(Key('dre-$chave')), findsNothing, reason: chave);
      }
      expect(find.text('Mostrar todas as linhas'), findsOneWidget);

      await tocar(tester, 'dre-mostrar-todas');
      for (final chave in zeradas) {
        expect(find.byKey(Key('dre-$chave')), findsOneWidget, reason: chave);
      }
      expect(find.text('Ocultar linhas sem valor'), findsOneWidget);

      await tocar(tester, 'dre-mostrar-todas');
      expect(find.byKey(const Key('dre-retencoes_na_fonte')), findsNothing);
    });

    testWidgets('subtotal e resultado aparecem mesmo valendo zero; sem linha zerada não há link',
        (tester) async {
      final financeiro = _FinanceiroCom(dre: Dre(
        papel: TipoUsuario.motoboy,
        dataInicio: DateTime(2026, 8, 1),
        dataFim: DateTime(2026, 8, 19),
        linhas: const [
          LinhaDre(chave: 'pagamentos_recebidos', rotulo: 'Pagamentos de turnos', valor: 50),
          LinhaDre(chave: 'das_mei', rotulo: 'DAS do MEI', valor: 50, subtrai: true),
          LinhaDre(
              chave: 'receita_liquida',
              rotulo: 'Receita líquida',
              valor: 0,
              tipo: TipoDeLinhaDre.subtotal),
          LinhaDre(
              chave: 'resultado',
              rotulo: 'Resultado do período',
              valor: 0,
              tipo: TipoDeLinhaDre.resultado),
        ],
        resultado: 0,
        situacao: SituacaoDre.equilibrio,
        lancamentosManuais: 1,
      ));
      await montarCom(tester, financeiro);

      expect(find.byKey(const Key('dre-receita_liquida')), findsOneWidget);
      expect(find.byKey(const Key('dre-resultado')), findsOneWidget);
      expect(find.byKey(const Key('dre-mostrar-todas')), findsNothing);
    });

    testWidgets(
        'com resultado negativo, "Lucro por hora" e "Lucro por turno" viram "Prejuízo por…", com o valor sem sinal',
        (tester) async {
      await montar(tester, comPrejuizo: true);
      Finder no(String chave, String texto) => find.descendant(
          of: find.byKey(Key('indicador-$chave')), matching: find.text(texto));

      expect(no('lucro-por-hora', 'Prejuízo por hora'), findsOneWidget);
      expect(no('lucro-por-hora', FormatoFiscal.moeda(19.25)), findsOneWidget);
      expect(no('lucro-por-turno', 'Prejuízo por turno'), findsOneWidget);
      expect(no('lucro-por-turno', FormatoFiscal.moeda(77.01)), findsOneWidget);
      expect(find.text('Lucro por hora'), findsNothing);
      // Sem sinal de menos nos dois cartões: quem diz "prejuízo" é o rótulo.
      for (final chave in ['lucro-por-hora', 'lucro-por-turno']) {
        expect(
            find.descendant(
                of: find.byKey(Key('indicador-$chave')), matching: find.textContaining('-')),
            findsNothing,
            reason: chave);
      }
      // A cor é a da faixa de prejuízo — e só reforça o que o rótulo já diz.
      final valor = tester.widget<Text>(no('lucro-por-hora', FormatoFiscal.moeda(19.25)));
      expect(valor.style!.color, VisualDaSituacao.prejuizo.cor);
    });

    testWidgets('com resultado positivo, os rótulos são "Lucro por hora" e "Lucro por turno"',
        (tester) async {
      await montar(tester);
      Finder no(String chave, String texto) => find.descendant(
          of: find.byKey(Key('indicador-$chave')), matching: find.text(texto));

      expect(no('lucro-por-hora', 'Lucro por hora'), findsOneWidget);
      expect(no('lucro-por-hora', FormatoFiscal.moeda(7)), findsOneWidget);
      expect(no('lucro-por-turno', 'Lucro por turno'), findsOneWidget);
      final valor = tester.widget<Text>(no('lucro-por-hora', FormatoFiscal.moeda(7)));
      expect(valor.style!.color, VisualDaSituacao.lucro.cor);
    });

    testWidgets('lojista: "Resultado por turno" vira "Prejuízo por turno" quando a operação dá prejuízo',
        (tester) async {
      final base = fakeDreLojista();
      await montarCom(
        tester,
        _FinanceiroCom(
          papel: TipoUsuario.lojista,
          dre: Dre(
            papel: TipoUsuario.lojista,
            dataInicio: base.dataInicio,
            dataFim: base.dataFim,
            linhas: base.linhas,
            resultado: -338,
            situacao: SituacaoDre.prejuizo,
            indicadores: const {'turnosFinalizados': 4, 'resultadoPorTurno': -84.5},
            lancamentosManuais: 2,
          ),
        ),
        papel: TipoUsuario.lojista,
      );
      Finder no(String texto) => find.descendant(
          of: find.byKey(const Key('indicador-resultado-por-turno')), matching: find.text(texto));

      expect(no('Prejuízo por turno'), findsOneWidget);
      expect(no(FormatoFiscal.moeda(84.5)), findsOneWidget);
      expect(find.text('Resultado por turno'), findsNothing);
    });

    testWidgets('lojista: a DRE da operação de entrega, com os indicadores dele',
        (tester) async {
      await montar(tester, papel: TipoUsuario.lojista);

      expect(find.byKey(const Key('dre-receita_de_entregas')), findsOneWidget);
      expect(find.byKey(const Key('dre-custo_dos_entregadores')), findsOneWidget);
      expect(find.byKey(const Key('dre-margem_da_operacao')), findsOneWidget);
      expect(find.text('= Resultado da operação de entrega'), findsOneWidget);
      expect(find.byKey(const Key('dre-combustivel')), findsNothing);

      for (final k in ['custo-sobre-receita', 'turnos', 'custo-por-turno', 'resultado-por-turno',
          'gorjetas']) {
        expect(find.byKey(Key('indicador-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('indicador-ponto-de-equilibrio')), findsNothing);
      expect(find.text('69,1%'), findsOneWidget);
    });

    testWidgets('indicadores do entregador, com o ponto de equilíbrio em turnos',
        (tester) async {
      await montar(tester);
      for (final k in ['margem', 'turnos', 'horas', 'lucro-por-hora', 'lucro-por-turno',
          'custo-por-km', 'ponto-de-equilibrio']) {
        expect(find.byKey(Key('indicador-$k')), findsOneWidget, reason: k);
      }
      expect(find.text('3 turnos'), findsOneWidget);
      expect(find.text('16,0 h'), findsOneWidget);
      expect(find.text('28,7%'), findsOneWidget);
    });

    testWidgets('sem ponto de equilíbrio, o cartão mostra "—" e diz o motivo', (tester) async {
      await montar(tester, comPrejuizo: true);

      expect(
          find.descendant(
              of: find.byKey(const Key('indicador-ponto-de-equilibrio')),
              matching: find.text('—')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('indicador-ponto-de-equilibrio')),
              matching: find.text('A margem por turno não cobre os custos variáveis')),
          findsOneWidget);
    });

    testWidgets('comparação com o período anterior: em reais e em palavras', (tester) async {
      await montar(tester);
      expect(find.text('Antes: prejuízo de ${FormatoFiscal.moeda(205.55)}'), findsOneWidget);
      expect(find.text('Melhorou ${FormatoFiscal.moeda(317.5)}'), findsOneWidget);
    });

    testWidgets('comparação quando piorou: diz "Piorou", com o valor sem sinal', (tester) async {
      await montar(tester, comPrejuizo: true);

      expect(find.text('Antes: lucro de ${FormatoFiscal.moeda(97)}'), findsOneWidget);
      expect(find.text('Piorou ${FormatoFiscal.moeda(405.05)}'), findsOneWidget);
    });
  });

  group('o período', () {
    testWidgets('abre no mês atual, e cada atalho pede o intervalo dele', (tester) async {
      final api = await montar(tester);

      expect(api.periodosPedidos.single, (DateTime(2026, 8, 1), dataAncoraGolden));
      expect(api.anosPedidos, [2026]);

      await tocar(tester, 'resultado-periodo-${AtalhoDePeriodo.mesAnterior.name}');
      expect(api.periodosPedidos.last, (DateTime(2026, 7, 1), DateTime(2026, 7, 31)));
    });

    testWidgets('tocar num mês do gráfico apura aquele mês — é como se chega ao mês retrasado',
        (tester) async {
      final api = await montar(tester);

      await tocar(tester, 'resultado-mes-6');

      expect(api.periodosPedidos.last, (DateTime(2026, 6, 1), DateTime(2026, 6, 30)));
      expect(find.byKey(const Key('resultado-periodo-mes')), findsOneWidget);
      expect(find.text('Junho de 2026'), findsOneWidget);
      // Nenhum atalho fica marcado: o período não é um deles.
      for (final a in AtalhoDePeriodo.values) {
        expect(
            tester.widget<ChoiceChip>(find.byKey(Key('resultado-periodo-${a.name}'))).selected,
            isFalse,
            reason: a.name);
      }
    });

    testWidgets('no celular os atalhos ficam numa linha só, que rola de lado', (tester) async {
      await montar(tester, viewport: const Size(360, 2600));

      final alturas = {
        for (final a in AtalhoDePeriodo.values)
          tester.getTopLeft(find.byKey(Key('resultado-periodo-${a.name}'))).dy,
      };
      expect(alturas, hasLength(1), reason: 'nenhuma ficha caiu para a linha de baixo');
      final linha = tester.widget<SingleChildScrollView>(
          find.byKey(const Key('resultado-periodo-linha')));
      expect(linha.scrollDirection, Axis.horizontal);
    });

    testWidgets('o mês escolhido no gráfico vem na frente dos atalhos, à vista sem rolar',
        (tester) async {
      await montar(tester, viewport: const Size(360, 2600));
      await tocar(tester, 'resultado-mes-6');

      final mes = tester.getTopLeft(find.byKey(const Key('resultado-periodo-mes')));
      final primeiroAtalho = tester.getTopLeft(
          find.byKey(Key('resultado-periodo-${AtalhoDePeriodo.values.first.name}')));
      expect(mes.dx, lessThan(primeiroAtalho.dx));
      expect(mes.dx, lessThan(360));
    });

    testWidgets('mês que ainda não chegou não é botão', (tester) async {
      final api = await montar(tester, viewport: desktopAlto);
      final antes = api.periodosPedidos.length;

      await tester.ensureVisible(find.byKey(const Key('resultado-mes-11')));
      await tester.tap(find.byKey(const Key('resultado-mes-11')), warnIfMissed: false);
      await tester.pump();

      expect(api.periodosPedidos, hasLength(antes));
    });

    testWidgets('o gráfico tem resumo em texto, e cada mês diz o próprio resultado',
        (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, comPrejuizo: true, viewport: desktopAlto);

      expect(
          find.bySemanticsLabel(RegExp(
              r'^Resultado mês a mês em 2026: abr receita R\$ 380, custos R\$ 278,05, '
              r'lucro de R\$ 101,95; .*ago receita R\$ 390, custos R\$ 698,05, '
              r'prejuízo de R\$ 308,05\.$')),
          findsOneWidget);
      final julho = find.bySemanticsLabel(RegExp(r'^Julho: receita R\$ 380, .*prejuízo de'));
      expect(julho, findsOneWidget);
      expect(tester.getSemantics(julho), isSemantics(isButton: true, hasTapAction: true));
      expect(find.bySemanticsLabel('Janeiro: sem movimento'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('as setas do gráfico trocam o ano, sem passar do ano atual', (tester) async {
      final api = await montar(tester);

      expect(tester.widget<IconButton>(find.byKey(const Key('resultado-ano-seguinte'))).onPressed,
          isNull);
      await tocar(tester, 'resultado-ano-anterior');

      expect(api.anosPedidos.last, 2025);
      expect(find.text('Sem movimento em 2025.'), findsOneWidget);
    });
  });

  group('os lançamentos', () {
    testWidgets('lista o que foi informado, com o sinal escrito e o recorrente dizendo o dia',
        (tester) async {
      await montar(tester);

      expect(find.byKey(const Key('lancamento-21')), findsOneWidget);
      expect(find.text('− ${FormatoFiscal.moeda(7.5)}'), findsOneWidget);
      expect(find.text('12/08/2026 · Gasolina do turno'), findsOneWidget);
      expect(find.text('Todo dia 5 · Parcela do consórcio da moto'), findsOneWidget);
    });

    testWidgets(
        'o que ainda vai começar aparece na lista dizendo que não conta, e dá para editar e excluir',
        (tester) async {
      await montarCom(
        tester,
        _FinanceiroCom(lancamentos: [
          LancamentoGerencial(
              id: 31,
              categoria: 'seguro',
              rotuloDaCategoria: 'Seguro',
              valor: 100,
              data: DateTime(2026, 8, 25),
              recorrente: true,
              ocorrenciasNoPeriodo: 0,
              valorNoPeriodo: 0),
        ]),
      );

      expect(find.text('Começa em 25/08/2026 · todo dia 25 · ainda não conta'), findsOneWidget);
      // O valor de uma ocorrência, e não "R$ 0,00".
      expect(find.text('− ${FormatoFiscal.moeda(100)}'), findsOneWidget);
      expect(find.byKey(const Key('lancamento-editar-31')), findsOneWidget);
      expect(find.byKey(const Key('lancamento-excluir-31')), findsOneWidget);
    });

    testWidgets('a receita informada pela loja aparece com "+"', (tester) async {
      await montar(tester, papel: TipoUsuario.lojista);

      expect(find.text('+ ${FormatoFiscal.moeda(208)}'), findsOneWidget);
      expect(find.text('− ${FormatoFiscal.moeda(45)}'), findsOneWidget);
    });

    testWidgets('excluir pede confirmação, e só então chama o backend e recarrega',
        (tester) async {
      final api = await montar(tester);
      final cargas = api.periodosPedidos.length;

      await tocar(tester, 'lancamento-excluir-21');
      expect(find.textContaining('Seu saldo não muda'), findsOneWidget);
      expect(api.excluidos, isEmpty);

      await tocar(tester, 'resultado-confirmar-exclusao');
      expect(api.excluidos, [21]);
      expect(api.periodosPedidos, hasLength(cargas + 1));
      expect(find.text('Lançamento excluído.'), findsOneWidget);
    });

    testWidgets('editar abre o formulário preenchido e salva pelo PUT', (tester) async {
      final api = await montar(tester);

      await tocar(tester, 'lancamento-editar-21');
      expect(find.text('Editar lançamento'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('lancamento-valor'))).controller!.text,
          '7,50');
      expect(tester.widget<TextFormField>(find.byKey(const Key('lancamento-km'))).controller!.text,
          '42,0');

      await tester.enterText(find.byKey(const Key('lancamento-valor')), '9,00');
      await tocar(tester, 'lancamento-salvar');

      expect(api.criados, isEmpty);
      final (id, enviado) = api.atualizados.single;
      expect(id, 21);
      expect(enviado.categoria, 'combustivel');
      expect(enviado.valor, 9.0);
      expect(enviado.km, 42.0);
      expect(find.text('Lançamento atualizado.'), findsOneWidget);
      // Um lançamento avulso não tem meses anteriores: não pergunta nada.
      expect(api.alcancesDasEdicoes, [null]);
    });

    testWidgets(
        'editar um recorrente de meses anteriores pergunta o alcance; o padrão aplica a partir deste mês',
        (tester) async {
      final api = await montar(tester);

      // A parcela de todo dia 5, desde abril. Hoje é 19/08/2026.
      await tocar(tester, 'lancamento-editar-23');
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '120');
      await tocar(tester, 'lancamento-salvar');

      expect(find.text('A mudança vale a partir de quando?'), findsOneWidget);
      expect(api.atualizados, isEmpty, reason: 'nada é salvo antes da escolha');
      // O padrão é o que preserva o passado: é ele o botão preenchido.
      expect(
          find.ancestor(
              of: find.text('Aplicar a partir deste mês'), matching: find.byType(FilledButton)),
          findsOneWidget);

      await tocar(tester, 'lancamento-aplicar-deste-mes');

      final (id, enviado) = api.atualizados.single;
      expect(id, 23);
      expect(enviado.valor, 120.0);
      expect(enviado.recorrente, isTrue);
      expect(api.alcancesDasEdicoes, [DateTime(2026, 8, 1)]);
      expect(find.text('Lançamento atualizado.'), findsOneWidget);
    });

    testWidgets('"Corrigir todos os meses" manda a edição sem data: o histórico inteiro muda',
        (tester) async {
      final api = await montar(tester);

      await tocar(tester, 'lancamento-editar-23');
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '120');
      await tocar(tester, 'lancamento-salvar');
      await tocar(tester, 'lancamento-corrigir-todos');

      expect(api.atualizados.single.$1, 23);
      expect(api.alcancesDasEdicoes, [null]);
    });

    testWidgets('fechar a pergunta sem escolher não salva, e o formulário continua aberto',
        (tester) async {
      final api = await montar(tester);

      await tocar(tester, 'lancamento-editar-23');
      await tocar(tester, 'lancamento-salvar');
      await tester.tap(find.text('Voltar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.atualizados, isEmpty);
      expect(find.text('Editar lançamento'), findsOneWidget);
    });

    testWidgets('desmarcar "repete todo mês" não pergunta: deixa de ser recorrente por inteiro',
        (tester) async {
      final api = await montar(tester);

      await tocar(tester, 'lancamento-editar-23');
      await tocar(tester, 'lancamento-recorrente');
      await tocar(tester, 'lancamento-salvar');

      expect(find.text('A mudança vale a partir de quando?'), findsNothing);
      expect(api.atualizados.single.$2.recorrente, isFalse);
      expect(api.alcancesDasEdicoes, [null]);
    });
  });

  group('o formulário', () {
    Future<void> abrir(WidgetTester tester) async {
      await tocar(tester, 'resultado-novo-lancamento');
      expect(find.byType(FormularioDeLancamento), findsOneWidget);
    }

    Future<void> escolherCategoria(WidgetTester tester, String rotulo) async {
      await tocar(tester, 'lancamento-categoria');
      await tester.tap(find.textContaining(rotulo).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('as categorias são as do papel, vindas do backend', (tester) async {
      await montar(tester, papel: TipoUsuario.lojista);
      await abrir(tester);
      await tocar(tester, 'lancamento-categoria');

      expect(find.textContaining('Taxa de entrega cobrada'), findsWidgets);
      expect(find.textContaining('Entrega fora do app'), findsWidgets);
      expect(find.textContaining('Combustível'), findsNothing);
    });

    testWidgets('a calculadora de combustível preenche o valor e os km', (tester) async {
      final api = await montar(tester);
      await abrir(tester);

      // Só aparece em "Combustível".
      expect(find.byKey(const Key('lancamento-calculadora')), findsNothing);
      await escolherCategoria(tester, 'Manutenção');
      expect(find.byKey(const Key('lancamento-calculadora')), findsNothing);
      await escolherCategoria(tester, 'Combustível');
      expect(find.byKey(const Key('lancamento-calculadora')), findsOneWidget);

      expect(tester.widget<TextButton>(find.byKey(const Key('calc-usar'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('calc-km')), '42');
      await tester.enterText(find.byKey(const Key('calc-consumo')), '35');
      await tester.enterText(find.byKey(const Key('calc-preco')), '6,25');
      await tester.pump();

      expect(tester.widget<Text>(find.byKey(const Key('calc-resultado'))).data,
          'Custo calculado: ${FormatoFiscal.moeda(7.5)}');
      await tocar(tester, 'calc-usar');

      expect(tester.widget<TextFormField>(find.byKey(const Key('lancamento-valor'))).controller!.text,
          '7,50');
      expect(tester.widget<TextFormField>(find.byKey(const Key('lancamento-km'))).controller!.text,
          '42,0');

      await tocar(tester, 'lancamento-salvar');
      final enviado = api.criados.single;
      expect(enviado.toJson(), {
        'categoria': 'combustivel',
        'valor': 7.5,
        'data': '2026-08-19',
        'recorrente': false,
        'km': 42.0,
      });
      expect(find.text('Lançamento salvo.'), findsOneWidget);
    });

    testWidgets('recorrente: o lançamento vai marcado, e a tela explica o dia', (tester) async {
      final api = await montar(tester);
      await abrir(tester);
      await escolherCategoria(tester, 'Seguro');
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '32');

      expect(find.byKey(const Key('lancamento-ate')), findsNothing);
      await tocar(tester, 'lancamento-recorrente');
      expect(find.byKey(const Key('lancamento-ate')), findsOneWidget);
      expect(find.textContaining('uma vez por mês, no dia 19'), findsOneWidget);
      expect(find.text('Sem data para acabar'), findsOneWidget);

      await tocar(tester, 'lancamento-salvar');
      final enviado = api.criados.single.toJson();
      expect(enviado['recorrente'], isTrue);
      expect(enviado.containsKey('recorrenteAte'), isFalse);
      expect(enviado['categoria'], 'seguro');
    });

    testWidgets('"1.500" é mil e quinhentos: o formulário mostra o valor lido e é ele que vai',
        (tester) async {
      final api = await montar(tester);
      await abrir(tester);
      await escolherCategoria(tester, 'Parcela');

      expect(find.byKey(const Key('lancamento-valor-lido')), findsNothing);
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '1.500');
      await tester.pump();
      expect(find.text('= ${FormatoFiscal.moeda(1500)}'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('lancamento-valor')), '12.5');
      await tester.pump();
      expect(find.text('= ${FormatoFiscal.moeda(12.5)}'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('lancamento-valor')), '1.500');
      await tocar(tester, 'lancamento-salvar');
      expect(api.criados.single.valor, 1500.0);
      expect(api.criados.single.toJson()['valor'], 1500.0);
    });

    testWidgets('a data do pagamento vai até hoje; o "até quando" do recorrente pode ser futuro',
        (tester) async {
      await montar(tester);
      await abrir(tester);
      final hoje = DateTime(2026, 8, 19);

      await tocar(tester, 'lancamento-data');
      expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate, hoje);
      await tester.tap(find.text('Cancelar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tocar(tester, 'lancamento-recorrente');
      await tocar(tester, 'lancamento-ate');
      expect(
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate.isAfter(hoje),
          isTrue);
    });

    testWidgets('valida antes de chamar o backend: categoria, valor e km', (tester) async {
      final api = await montar(tester);
      await abrir(tester);

      await tocar(tester, 'lancamento-salvar');
      expect(find.text('Escolha a categoria'), findsOneWidget);
      expect(find.text('Informe o valor'), findsOneWidget);

      await escolherCategoria(tester, 'Manutenção');
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '0');
      await tester.enterText(find.byKey(const Key('lancamento-km')), '0');
      await tocar(tester, 'lancamento-salvar');
      expect(find.text('O valor deve ser maior que zero'), findsOneWidget);
      expect(find.text('Informe os km, ou deixe em branco'), findsOneWidget);

      expect(api.criados, isEmpty);
    });

    testWidgets('o erro do backend aparece no formulário, que continua aberto', (tester) async {
      final api = await montar(tester,
          erroAoSalvar: const ApiException(400, 'Informe um turno de que você participou.'));
      await abrir(tester);
      await escolherCategoria(tester, 'Manutenção');
      await tester.enterText(find.byKey(const Key('lancamento-valor')), '45');
      await tocar(tester, 'lancamento-salvar');

      expect(find.byKey(const Key('lancamento-erro')), findsOneWidget);
      expect(find.text('Informe um turno de que você participou.'), findsOneWidget);
      expect(find.byType(FormularioDeLancamento), findsOneWidget);
      expect(api.criados, isEmpty);
    });

    testWidgets('no celular o formulário é uma folha inferior', (tester) async {
      await montar(tester);
      await abrir(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('no desktop o formulário é um diálogo', (tester) async {
      await montar(tester, viewport: desktopAlto);
      await abrir(tester);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('navegação', () {
    for (final papel in TipoUsuario.values) {
      testWidgets('${papel.name}: o menu tem "Resultado", e o cartão dos relatórios leva até lá',
          (tester) async {
        final app = await montarApp(
          tester,
          papel: papel,
          largura: const Size(1440, 1024),
          rota: AppRoutes.relatorioFinanceiro,
        );

        expect(find.text('Resultado'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('relatorio-ver-resultado')));
        await tester.tap(find.byKey(const Key('relatorio-ver-resultado')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(ResultadoScreen), findsOneWidget);
        // Troca de seção: a pilha passa a ser só a tela de resultado.
        expect(app.paginas, [AppRoutes.resultado]);
      });
    }
  });
}

/// O financeiro com a DRE ou a lista que o teste escolhe.
class _FinanceiroCom extends FakeFinanceiroApi {
  _FinanceiroCom({super.papel, this.dre, this.lancamentos});

  final Dre? dre;
  final List<LancamentoGerencial>? lancamentos;

  @override
  Future<Dre> buscarDre({DateTime? dataInicio, DateTime? dataFim}) async =>
      dre ?? await super.buscarDre(dataInicio: dataInicio, dataFim: dataFim);

  @override
  Future<List<LancamentoGerencial>> listarLancamentos({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async =>
      lancamentos ??
      await super.listarLancamentos(dataInicio: dataInicio, dataFim: dataFim);
}

/// O fake da API com o financeiro que o teste escolhe.
class _Api extends FakeApiService {
  _Api(TipoUsuario papel, this._financeiroDoTeste) : super(tipoUsuario: papel);

  final FakeFinanceiroApi _financeiroDoTeste;

  @override
  FinanceiroApi get financeiro => _financeiroDoTeste;
}
