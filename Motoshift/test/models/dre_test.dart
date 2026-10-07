import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moto_shift/models/dre.dart';
import 'package:moto_shift/models/lancamento_gerencial.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/utils/formato_fiscal.dart';
import 'package:moto_shift/utils/resumo_acessivel.dart';
import 'package:moto_shift/views/resultado/lancamento_form.dart';

/// Os modelos da DRE (RF13 / SCRUM-47) e as contas que a tela faz sem
/// backend: a frase da situação, o JSON do lançamento, a calculadora de
/// combustível e o número digitado com vírgula.
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Dre.fromJson', () {
    test('lê a resposta completa do backend', () {
      final dre = Dre.fromJson({
        'papel': 'motoboy',
        'dataInicio': '2026-09-01',
        'dataFim': '2026-09-30',
        'linhas': [
          {
            'chave': 'pagamentos_recebidos',
            'rotulo': 'Pagamentos de turnos',
            'valor': 380.0,
            'tipo': 'linha',
            'origem': 'extrato',
            'subtrai': false,
          },
          {
            'chave': 'combustivel',
            'rotulo': 'Combustível',
            'valor': 30,
            'tipo': 'linha',
            'origem': 'manual',
            'subtrai': true,
          },
          {
            'chave': 'resultado',
            'rotulo': 'Resultado do período',
            'valor': 350,
            'tipo': 'resultado',
            'origem': 'calculado',
            'subtrai': false,
          },
        ],
        'resultado': 350,
        'situacao': 'lucro',
        'indicadores': {
          'margemLiquida': 92.11,
          'turnosPagos': 4,
          'custoPorKm': null,
          'pontoDeEquilibrioTurnos': null,
          'pontoDeEquilibrioMotivo': 'sem turnos pagos no período',
        },
        'anterior': {
          'dataInicio': '2026-08-02',
          'dataFim': '2026-08-31',
          'resultado': -205.55,
          'situacao': 'prejuizo',
        },
        'variacaoResultado': 555.55,
        'lancamentosManuais': 1,
      });

      expect(dre.papel, TipoUsuario.motoboy);
      expect(dre.dataInicio, DateTime(2026, 9, 1));
      expect(dre.dataFim, DateTime(2026, 9, 30));
      expect(dre.linhas, hasLength(3));
      expect(dre.linha('combustivel')!.rotuloComSinal, '(−) Combustível');
      expect(dre.linha('combustivel')!.origem, OrigemDaLinha.manual);
      expect(dre.linha('pagamentos_recebidos')!.rotuloComSinal, 'Pagamentos de turnos');
      expect(dre.linha('resultado')!.tipo, TipoDeLinhaDre.resultado);
      expect(dre.situacao, SituacaoDre.lucro);
      expect(dre.numero('margemLiquida'), 92.11);
      expect(dre.inteiro('turnosPagos'), 4);
      expect(dre.numero('custoPorKm'), isNull);
      expect(dre.texto('pontoDeEquilibrioMotivo'), 'sem turnos pagos no período');
      expect(dre.anterior!.situacao, SituacaoDre.prejuizo);
      expect(dre.anterior!.resultado, -205.55);
      expect(dre.variacaoResultado, 555.55);
      expect(dre.lancamentosManuais, 1);
    });

    test('tolera campo ausente: sem linhas, sem indicadores e sem período anterior', () {
      final dre = Dre.fromJson({'papel': 'lojista'});

      expect(dre.papel, TipoUsuario.lojista);
      expect(dre.souLojista, isTrue);
      expect(dre.linhas, isEmpty);
      expect(dre.resultado, 0);
      // Sem situação, o estado que não comemora nem alarma.
      expect(dre.situacao, SituacaoDre.equilibrio);
      expect(dre.indicadores, isEmpty);
      expect(dre.numero('margemLiquida'), isNull);
      expect(dre.inteiro('turnosPagos'), isNull);
      expect(dre.anterior, isNull);
      expect(dre.variacaoResultado, isNull);
      expect(dre.lancamentosManuais, 0);
      expect(dre.linha('resultado'), isNull);
    });

    test('linha sem tipo, origem ou sinal vira linha comum, calculada, que não subtrai', () {
      final dre = Dre.fromJson({
        'linhas': [
          {'chave': 'x', 'rotulo': 'X'},
          'isto não é uma linha',
        ],
        'situacao': 'uma situação que o app não conhece',
        'anterior': {'resultado': 10},
      });

      expect(dre.linhas, hasLength(1));
      final x = dre.linhas.single;
      expect(x.valor, 0);
      expect(x.tipo, TipoDeLinhaDre.linha);
      expect(x.origem, OrigemDaLinha.calculado);
      expect(x.subtrai, isFalse);
      expect(dre.situacao, SituacaoDre.equilibrio);
      // Período anterior sem datas não serve para comparar.
      expect(dre.anterior, isNull);
    });

    test('a frase diz a situação por extenso, com o valor sem sinal', () {
      Dre com(double resultado, String situacao) =>
          Dre.fromJson({'resultado': resultado, 'situacao': situacao});

      expect(com(1240, 'lucro').frase, 'Lucro de ${FormatoFiscal.moeda(1240)} no período');
      expect(com(-310, 'prejuizo').frase, 'Prejuízo de ${FormatoFiscal.moeda(310)} no período');
      expect(com(0, 'equilibrio').frase, 'Sem lucro nem prejuízo no período');
      expect(FormatoFiscal.moeda(1240), contains('1.240,00'));
    });
  });

  group('MesDre e o resumo do gráfico', () {
    test('lê o mês e reconhece o mês sem movimento', () {
      final ago = MesDre.fromJson(
          {'mes': 8, 'rotulo': 'Ago', 'receita': 380, 'custos': 705.55, 'resultado': -325.55});
      expect(ago.mes, 8);
      expect(ago.resultado, -325.55);
      expect(ago.semMovimento, isFalse);
      expect(MesDre.fromJson({'mes': 1}).semMovimento, isTrue);
    });

    test('o leitor de tela ouve só os meses com movimento, com a situação em palavras', () {
      expect(
        resumoDoResultadoMensal(2026, [
          (rotulo: 'Jul', receita: 0.0, custos: 0.0, resultado: 0.0),
          (rotulo: 'Ago', receita: 380.0, custos: 705.55, resultado: -325.55),
          (rotulo: 'Set', receita: 475.0, custos: 285.5, resultado: 189.5),
          (rotulo: 'Out', receita: 100.0, custos: 100.0, resultado: 0.0),
        ]),
        r'Resultado mês a mês em 2026: '
        r'ago receita R$ 380, custos R$ 705,55, prejuízo de R$ 325,55; '
        r'set receita R$ 475, custos R$ 285,50, lucro de R$ 189,50; '
        r'out receita R$ 100, custos R$ 100, sem lucro nem prejuízo.',
      );
      expect(resumoDoResultadoMensal(2025, const []), 'Resultado mês a mês em 2025: sem movimento.');
    });
  });

  group('LancamentoGerencial', () {
    test('lê o lançamento da listagem, com as ocorrências do período', () {
      final l = LancamentoGerencial.fromJson({
        'id': 7,
        'categoria': 'parcela_ou_aluguel_veiculo',
        'rotuloDaCategoria': 'Parcela ou aluguel do veículo',
        'grupo': 'despesa_fixa',
        'soma': false,
        'valor': 95.0,
        'data': '2026-04-05',
        'recorrente': true,
        'recorrenteAte': '2027-04-05',
        'ocorrenciasNoPeriodo': 3,
        'valorNoPeriodo': 285.0,
      });

      expect(l.id, 7);
      expect(l.recorrente, isTrue);
      expect(l.data, DateTime(2026, 4, 5));
      expect(l.recorrenteAte, DateTime(2027, 4, 5));
      expect(l.valorExibido, 285.0);
      expect(l.soma, isFalse);
    });

    test('tolera campo ausente: o rótulo cai para a categoria e o peso para o valor', () {
      final l = LancamentoGerencial.fromJson({'categoria': 'seguro', 'valor': 32});

      expect(l.id, isNull);
      expect(l.rotuloDaCategoria, 'seguro');
      expect(l.recorrente, isFalse);
      expect(l.recorrenteAte, isNull);
      expect(l.km, isNull);
      expect(l.ocorrenciasNoPeriodo, isNull);
      expect(l.valorExibido, 32);
    });

    test('o JSON de envio leva só o que o usuário preenche', () {
      final completo = LancamentoGerencial(
        id: 9,
        categoria: 'combustivel',
        rotuloDaCategoria: 'Combustível',
        valor: 7.5,
        data: DateTime(2026, 8, 12),
        turnoId: 4,
        km: 42,
        descricao: '  Gasolina do turno ',
        ocorrenciasNoPeriodo: 1,
        valorNoPeriodo: 7.5,
      ).toJson();
      expect(completo, {
        'categoria': 'combustivel',
        'valor': 7.5,
        'data': '2026-08-12',
        'recorrente': false,
        'turnoId': 4,
        'km': 42.0,
        'descricao': 'Gasolina do turno',
      });

      // "Até" só vai com a recorrência ligada; opcional vazio não vai.
      final avulso = LancamentoGerencial(
        categoria: 'seguro',
        valor: 32,
        data: DateTime(2026, 8, 15),
        recorrenteAte: DateTime(2027, 1, 15),
        descricao: '   ',
      ).toJson();
      expect(avulso.containsKey('recorrenteAte'), isFalse);
      expect(avulso.containsKey('descricao'), isFalse);
      expect(avulso.containsKey('km'), isFalse);

      final recorrente = LancamentoGerencial(
        categoria: 'seguro',
        valor: 32,
        data: DateTime(2026, 8, 15),
        recorrente: true,
        recorrenteAte: DateTime(2027, 1, 15),
      ).toJson();
      expect(recorrente['recorrente'], isTrue);
      expect(recorrente['recorrenteAte'], '2027-01-15');
    });

    test('só a categoria de combustível tem a calculadora', () {
      expect(const CategoriaDeLancamento(valor: 'combustivel', rotulo: 'Combustível').ehCombustivel,
          isTrue);
      expect(const CategoriaDeLancamento(valor: 'manutencao', rotulo: 'Manutenção').ehCombustivel,
          isFalse);
      final c = CategoriaDeLancamento.fromJson({'valor': 'das_mei'});
      expect(c.rotulo, 'das_mei');
      expect(c.soma, isFalse);
    });
  });

  group('calculadora de combustível', () {
    test('km rodados ÷ consumo × preço do litro, em centavos', () {
      // A conta da massa de demonstração: 42 km ÷ 35 km/l × R$ 6,25.
      expect(custoDoCombustivel(km: 42, consumoKmPorLitro: 35, precoDoLitro: 6.25), 7.5);
      expect(custoDoCombustivel(km: 120, consumoKmPorLitro: 30, precoDoLitro: 6.19), 24.76);
      // Arredonda para o centavo.
      expect(custoDoCombustivel(km: 100, consumoKmPorLitro: 33, precoDoLitro: 6.29), 19.06);
    });

    test('sem os três números, ou com algum que não é positivo, não calcula', () {
      expect(custoDoCombustivel(km: null, consumoKmPorLitro: 35, precoDoLitro: 6.25), isNull);
      expect(custoDoCombustivel(km: 42, consumoKmPorLitro: null, precoDoLitro: 6.25), isNull);
      expect(custoDoCombustivel(km: 42, consumoKmPorLitro: 35, precoDoLitro: null), isNull);
      expect(custoDoCombustivel(km: 42, consumoKmPorLitro: 0, precoDoLitro: 6.25), isNull);
      expect(custoDoCombustivel(km: -1, consumoKmPorLitro: 35, precoDoLitro: 6.25), isNull);
      expect(custoDoCombustivel(km: 42, consumoKmPorLitro: 35, precoDoLitro: 0), isNull);
    });
  });

  group('número digitado (SCRUM-49)', () {
    test('com vírgula, ela é o decimal e o ponto é milhar', () {
      expect(numeroDigitado('7,50'), 7.5);
      expect(numeroDigitado('1.500,00'), 1500);
      expect(numeroDigitado(' 1.234,56 '), 1234.56);
      expect(numeroDigitado('1.234.567,8'), 1234567.8);
    });

    test('sem vírgula, ponto seguido de exatamente três dígitos, em um ou mais grupos, é milhar',
        () {
      // O defeito: "1.500" era lido como 1,5 — uma parcela de R$ 1.500 era
      // salva como R$ 1,50.
      expect(numeroDigitado('1.500'), 1500);
      expect(numeroDigitado('12.500'), 12500);
      expect(numeroDigitado('1.234.567'), 1234567);
      expect(numeroDigitado('999.999'), 999999);
    });

    test('qualquer outro ponto é decimal', () {
      expect(numeroDigitado('12.5'), 12.5);
      expect(numeroDigitado('0.75'), 0.75);
      expect(numeroDigitado('1.50'), 1.5);
      expect(numeroDigitado('7.50'), 7.5);
      expect(numeroDigitado('1.5000'), 1.5);
      // Zero à esquerda não abre grupo de milhar, e grupo de quatro dígitos
      // não é milhar.
      expect(numeroDigitado('0.750'), 0.75);
      expect(numeroDigitado('1234.567'), 1234.567);
    });

    test('sem separador é o número; o que não é número é nulo', () {
      expect(numeroDigitado('42'), 42);
      expect(numeroDigitado('1500'), 1500);
      expect(numeroDigitado(''), isNull);
      expect(numeroDigitado('   '), isNull);
      expect(numeroDigitado('abc'), isNull);
      expect(numeroDigitado('1.2.3'), isNull);
      expect(numeroDigitado('1,2,3'), isNull);
    });

    test('preço do litro e consumo: três casas depois do ponto são decimais', () {
      expect(numeroDigitado('5.899', pontoPodeSerMilhar: false), 5.899);
      expect(numeroDigitado('5,899', pontoPodeSerMilhar: false), 5.899);
      // A vírgula continua mandando: com ela, o ponto é milhar.
      expect(numeroDigitado('1.234,5', pontoPodeSerMilhar: false), 1234.5);
    });
  });
}
