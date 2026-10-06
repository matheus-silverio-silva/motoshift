// O que o leitor de tela diz onde só havia desenho (SCRUM-40): gráficos,
// mapas, estrelas e os botões que eram um ícone sem nome.
//
// As diretrizes do `diretrizes_test.dart` perguntam se tudo o que é clicável
// tem rótulo. Aqui a pergunta é outra: o rótulo diz a coisa certa?

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/utils/resumo_acessivel.dart';
import 'package:moto_shift/utils/serie_diaria.dart';
import 'package:moto_shift/widgets/app_header.dart';
import 'package:moto_shift/widgets/desktop/weekly_bar_chart_card.dart';
import 'package:moto_shift/widgets/mapa_raio.dart';
import 'package:moto_shift/widgets/mapa_turno.dart';
import 'package:moto_shift/widgets/mini_bar_chart.dart';
import 'package:moto_shift/widgets/olho_da_senha.dart';
import 'package:moto_shift/widgets/rating_stars.dart';

import '../test_helpers.dart';

Future<void> _montar(WidgetTester tester, Widget child,
    {Size viewport = const Size(390, 844)}) {
  return pumpGolden(
    tester,
    child: Scaffold(body: Center(child: child)),
    viewport: viewport,
  );
}

void main() {
  setUpAll(setupGoldenTests);

  group('as frases', () {
    test('valor redondo não ganha centavos; quebrado ganha vírgula', () {
      expect(reaisFalados(120), r'R$ 120');
      expect(reaisFalados(0), r'R$ 0');
      expect(reaisFalados(87.5), r'R$ 87,50');
    });

    test('quilômetro: "5 km" e "2,5 km"', () {
      expect(kmFalados(5), '5 km');
      expect(kmFalados(2.5), '2,5 km');
    });

    test('gráfico: cada dia junto do que rendeu, na ordem', () {
      expect(
        resumoDeBarras(
          titulo: 'Ganhos da semana',
          rotulos: ['Seg', 'Ter', 'Qua'],
          valores: [120, 0, 87.5],
        ),
        r'Ganhos da semana: seg R$ 120, ter R$ 0, qua R$ 87,50.',
      );
    });

    test('gráfico zerado diz que não há valor, em vez de sete zeros', () {
      expect(
        resumoDeBarras(
          titulo: 'Ganhos da semana',
          rotulos: ['Seg', 'Ter'],
          valores: [0, 0],
        ),
        'Ganhos da semana: sem valores no período.',
      );
      expect(
        resumoDeBarras(titulo: 'Ganhos', rotulos: [], valores: []),
        'Ganhos: sem valores no período.',
      );
    });

    test('mapa: só entra o que está desenhado', () {
      expect(
        resumoDoMapa(local: 'Rua das Flores, 100', raioKm: 5, pontos: 3),
        'Mapa: Rua das Flores, 100. Raio de 5 km. 3 pontos marcados.',
      );
      expect(resumoDoMapa(local: 'Centro', pontos: 1),
          'Mapa: Centro. 1 ponto marcado.');
      expect(resumoDoMapa(raioKm: 2.5), 'Mapa: Raio de 2,5 km.');
      expect(resumoDoMapa(), 'Mapa.');
    });

    test('nota: "Nota 4 de 5", e "Sem nota" antes da primeira estrela', () {
      expect(resumoDaNota(4), 'Nota 4 de 5');
      expect(resumoDaNota(0), 'Sem nota');
    });
  });

  group('gráficos', () {
    testWidgets('o gráfico do celular vira uma frase só, com os valores',
        (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        const SizedBox(
          width: 300,
          child: MiniBarChart(
            titulo: 'Ganhos dos últimos 7 dias',
            values: [120, 0, 90],
            labels: ['Seg', 'Ter', 'Qua'],
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
            r'Ganhos dos últimos 7 dias: seg R$ 120, ter R$ 0, qua R$ 90.'),
        findsOneWidget,
      );
      // Os dias continuam DESENHADOS, mas não são lidos soltos — já estão na
      // frase, e lidos duas vezes seriam ruído.
      expect(find.text('Seg'), findsOneWidget);
      expect(find.bySemanticsLabel('Seg'), findsNothing);
      semantica.dispose();
    });

    testWidgets('o gráfico do desktop também, com o título do card',
        (tester) async {
      final semantica = tester.ensureSemantics();
      final base = DateTime(2025, 8, 11); // uma segunda-feira
      await _montar(
        tester,
        SizedBox(
          width: 620,
          child: WeeklyBarChartCard(
            title: 'Gasto com turnos',
            pontos: [
              PontoDiario(dia: base, label: 'Seg', valor: 150),
              PontoDiario(
                  dia: base.add(const Duration(days: 1)),
                  label: 'Ter',
                  valor: 0),
              PontoDiario(
                  dia: base.add(const Duration(days: 2)),
                  label: 'Qua',
                  valor: 80),
            ],
          ),
        ),
        viewport: const Size(1000, 700),
      );

      expect(
        find.bySemanticsLabel(
            r'Gasto com turnos: seg R$ 150, ter R$ 0, qua R$ 80.'),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  group('estrelas', () {
    testWidgets('só exibindo, é um nó único: "Nota 4 de 5"', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, const RatingStars(rating: 4));

      expect(find.bySemanticsLabel('Nota 4 de 5'), findsOneWidget);
      // Nem as estrelas nem o "Muito bom · 4 de 5" são lidos à parte.
      expect(find.bySemanticsLabel('4 estrelas'), findsNothing);
      expect(find.bySemanticsLabel('Muito bom · 4 de 5'), findsNothing);
      semantica.dispose();
    });

    testWidgets('para dar a nota, cada estrela é um botão com nome',
        (tester) async {
      final semantica = tester.ensureSemantics();
      var nota = 2;
      await _montar(
        tester,
        StatefulBuilder(
          builder: (context, setState) => RatingStars(
            rating: nota,
            onRatingChanged: (n) => setState(() => nota = n),
          ),
        ),
      );

      expect(find.bySemanticsLabel('1 estrela'), findsOneWidget);
      for (var n = 2; n <= 5; n++) {
        expect(find.bySemanticsLabel('$n estrelas'), findsOneWidget);
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 estrelas')),
        isSemantics(label: '2 estrelas', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('4 estrelas')),
        isSemantics(label: '4 estrelas', isButton: true, isSelected: false),
      );

      await tester.tap(find.bySemanticsLabel('4 estrelas'));
      await tester.pump();

      expect(nota, 4);
      expect(
        tester.getSemantics(find.bySemanticsLabel('4 estrelas')),
        isSemantics(label: '4 estrelas', isButton: true, isSelected: true),
      );
      expect(find.text('Muito bom · 4 de 5'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('mapas', () {
    testWidgets('o mapa diz o lugar, o raio e quantos pinos tem',
        (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        const SizedBox(
          width: 340,
          child: MapaRaio(
            centro: LatLng(-23.55, -46.63),
            raioKm: 5,
            rodape: 'Vila Mariana',
            pontos: [
              MapaPonto(posicao: LatLng(-23.56, -46.64), rotulo: r'R$ 90'),
              MapaPonto(posicao: LatLng(-23.54, -46.62), rotulo: r'R$ 70'),
            ],
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
            'Mapa: Vila Mariana. Raio de 5 km. 2 pontos marcados.'),
        findsOneWidget,
      );
      // A etiqueta do canto está desenhada, mas não é lida de novo.
      expect(find.text('Vila Mariana'), findsOneWidget);
      expect(find.bySemanticsLabel('Vila Mariana'), findsNothing);
      semantica.dispose();
    });

    testWidgets('pino clicável é um botão com o nome do que abre',
        (tester) async {
      final semantica = tester.ensureSemantics();
      var abriu = false;
      await _montar(
        tester,
        SizedBox(
          width: 340,
          child: MapaRaio(
            centro: const LatLng(-23.55, -46.63),
            raioKm: 5,
            pontos: [
              MapaPonto(
                posicao: const LatLng(-23.551, -46.631),
                rotulo: r'R$ 90',
                descricao: r'Turno Jantar de sexta, R$ 90, a 1,2 km',
                onTap: () => abriu = true,
              ),
            ],
          ),
        ),
      );

      final pino =
          find.bySemanticsLabel(r'Turno Jantar de sexta, R$ 90, a 1,2 km');
      expect(pino, findsOneWidget);
      // Nome E ação: um botão que o leitor de tela anuncia e não consegue
      // acionar é pior do que nenhum.
      expect(tester.getSemantics(pino),
          isSemantics(isButton: true, hasTapAction: true));

      tester.semantics.tap(find.semantics.byLabel(
          r'Turno Jantar de sexta, R$ 90, a 1,2 km'));
      expect(abriu, isTrue);
      semantica.dispose();
    });

    testWidgets('o mapa do turno diz de onde ele parte e até onde vai',
        (tester) async {
      final semantica = tester.ensureSemantics();
      final turno = Turno(
        id: 7,
        lojistId: 2,
        titulo: 'Jantar de sexta',
        regiao: 'Água Verde, Curitiba',
        endereco: 'Av. República Argentina, 1000',
        latitude: -25.4505,
        longitude: -49.2850,
        dataInicio: DateTime(2025, 8, 15, 18),
        dataFim: DateTime(2025, 8, 15, 23),
        valorEstimado: 120,
        raioEntregaKm: 8,
      );

      await _montar(tester, SizedBox(width: 340, child: MapaTurno(turno: turno)));

      expect(
        find.bySemanticsLabel(
          'Mapa do turno: ponto de partida em Av. República Argentina, 1000. '
          'Raio de entrega de 8 km.',
        ),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  group('botões que eram só um ícone', () {
    testWidgets('o olho da senha diz o que faz, e muda com o estado',
        (tester) async {
      final semantica = tester.ensureSemantics();
      var visivel = false;
      await _montar(
        tester,
        StatefulBuilder(
          builder: (context, setState) => OlhoDaSenha(
            visivel: visivel,
            onTap: () => setState(() => visivel = !visivel),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Mostrar senha'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Mostrar senha')),
          isSemantics(isButton: true));

      await tester.tap(find.byType(OlhoDaSenha));
      await tester.pump();

      expect(visivel, isTrue);
      expect(find.bySemanticsLabel('Ocultar senha'), findsOneWidget);
      expect(find.bySemanticsLabel('Mostrar senha'), findsNothing);
      semantica.dispose();
    });

    testWidgets('a seta do cabeçalho se chama "Voltar"', (tester) async {
      final semantica = tester.ensureSemantics();
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Column(
            children: [AppHeader.back(title: 'Carteira', onBack: () {})],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Voltar'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Voltar')),
          isSemantics(isButton: true));
      semantica.dispose();
    });

    testWidgets('o sino diz quantas notificações há por ler', (tester) async {
      final semantica = tester.ensureSemantics();

      // Um notifier, e não três `pumpGolden`: a rota guarda o primeiro `child`
      // que recebeu, e montar de novo não trocaria o cabeçalho.
      final naoLidas = ValueNotifier<int>(0);
      addTearDown(naoLidas.dispose);
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Column(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: naoLidas,
                builder: (context, n, _) => AppHeader.greeting(
                  greeting: 'Boa tarde,',
                  name: 'Rafael',
                  avatarInitials: 'RA',
                  notificacoes: n,
                  onNotificacoes: () {},
                ),
              ),
            ],
          ),
        ),
      );

      Future<void> comNaoLidas(int n) async {
        naoLidas.value = n;
        await tester.pump();
      }

      await comNaoLidas(0);
      expect(find.bySemanticsLabel('Notificações'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Notificações')),
          isSemantics(isButton: true, hasTapAction: true));

      await comNaoLidas(1);
      expect(find.bySemanticsLabel('Notificações, 1 não lida'), findsOneWidget);

      await comNaoLidas(4);
      expect(
          find.bySemanticsLabel('Notificações, 4 não lidas'), findsOneWidget);
      // O número do selo não é lido solto: "4, botão" não dizia nada.
      expect(find.bySemanticsLabel('4'), findsNothing);
      semantica.dispose();
    });
  });
}
