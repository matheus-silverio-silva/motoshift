// Quem emite a nota fiscal: o lojista, e só ele.
//
// O documento é o mesmo para os dois lados — o entregador presta, o lojista
// toma —, mas o botão não é. Estes testes prendem o que a regra muda na tela:
// o entregador nunca vê "Emitir" nem "Cancelar", a nota que a loja ainda não
// emitiu aparece como "aguardando", sem botão, e a nota já emitida chega a ele
// por consulta (GET), nunca por um pedido de emissão (POST).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/documento_fiscal.dart';
import 'package:moto_shift/models/nota_fiscal.dart';
import 'package:moto_shift/models/transacao.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/pendencias_provider.dart';
import 'package:moto_shift/services/api/carteira_api.dart';
import 'package:moto_shift/services/api/nota_fiscal_api.dart';
import 'package:moto_shift/views/extrato/lancamento_detalhe_screen.dart';
import 'package:moto_shift/views/notas_fiscais/nota_fiscal_detalhe.dart';
import 'package:moto_shift/views/notas_fiscais/notas_fiscais_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(setupGoldenTests);

  group('Tela de notas', () {
    testWidgets('para o entregador, o que falta é "aguardando emissão", sem botão',
        (tester) async {
      await pumpGolden(
        tester,
        child: const NotasFiscaisScreen(),
        tipoUsuario: TipoUsuario.motoboy,
        apiFake: _Api(pendentes: [_pendente('prestador')]),
      );

      expect(find.text('Aguardando emissão'), findsOneWidget);
      expect(find.byKey(const Key('notas-aguardando-emissao')), findsOneWidget);
      expect(find.byKey(const Key('notas-emitir')), findsNothing);
      expect(find.text('A emitir'), findsNothing);
    });

    testWidgets('para o lojista, o mesmo dado é "a emitir", com botão',
        (tester) async {
      await pumpGolden(
        tester,
        child: const NotasFiscaisScreen(),
        tipoUsuario: TipoUsuario.lojista,
        apiFake: _Api(pendentes: [_pendente('tomador')]),
      );

      expect(find.text('A emitir'), findsOneWidget);
      expect(find.byKey(const Key('notas-emitir')), findsOneWidget);
      expect(find.byKey(const Key('notas-aguardando-emissao')), findsNothing);
    });
  });

  group('Detalhe da nota', () {
    testWidgets('o entregador vê, baixa e imprime — não cancela', (tester) async {
      await pumpGolden(
        tester,
        tipoUsuario: TipoUsuario.motoboy,
        child: Scaffold(
            body: NotaFiscalDetalhe(nota: fakeNotaFiscal(papel: 'prestador'))),
      );

      expect(find.byKey(const Key('documento-baixar-pdf')), findsOneWidget);
      expect(find.byKey(const Key('documento-imprimir')), findsOneWidget);
      expect(find.text('Cancelar nota fiscal'), findsNothing);
    });

    testWidgets('o lojista, que emitiu, é quem cancela', (tester) async {
      await pumpGolden(
        tester,
        tipoUsuario: TipoUsuario.lojista,
        child: Scaffold(
            body: NotaFiscalDetalhe(nota: fakeNotaFiscal(papel: 'tomador'))),
      );

      expect(find.text('Cancelar nota fiscal'), findsOneWidget);
    });
  });

  group('Lançamento do entregador', () {
    testWidgets('nota ainda não emitida: aviso no lugar do botão', (tester) async {
      await pumpGolden(
        tester,
        child: LancamentoDetalheScreen(lancamento: _recebido(documentoId: null)),
      );

      expect(find.byKey(const Key('lancamento-aguardando-emissao')), findsOneWidget);
      expect(find.text('Aguardando emissão pelo lojista'), findsOneWidget);
      expect(find.byKey(const Key('lancamento-gerar-documento')), findsNothing);
      expect(find.text('Gerar nota fiscal'), findsNothing);
    });

    testWidgets('nota já emitida: abre por consulta, nunca pedindo emissão',
        (tester) async {
      final api = _Api();

      await pumpGolden(
        tester,
        apiFake: api,
        child: LancamentoDetalheScreen(lancamento: _recebido(documentoId: 77)),
      );
      await tester.tap(find.text('Ver nota fiscal'));
      await tester.pumpAndSettle();

      expect(api.carteiraFake.documentosBuscados, [92]);
      expect(api.carteiraFake.documentosGerados, isEmpty);
    });

    testWidgets('comprovante continua sendo gerado pelo dono, como antes',
        (tester) async {
      final api = _Api();
      final recarga = fakeExtrato().firstWhere((t) => t.id == 91);

      await pumpGolden(
        tester,
        apiFake: api,
        child: LancamentoDetalheScreen(lancamento: recarga),
      );
      await tester.tap(find.byKey(const Key('lancamento-gerar-documento')));
      await tester.pumpAndSettle();

      expect(api.carteiraFake.documentosGerados, [91]);
    });
  });

  group('Pendências', () {
    test('nota sem emissão é pendência do lojista e informação do entregador',
        () async {
      final doEntregador = PendenciasProvider(_Api(pendentes: [_pendente('prestador')]));
      await doEntregador.carregar(fakeMotoboy());
      expect(doEntregador.quantidadeNotas, 0);
      expect(doEntregador.notasDoTurno(202), isEmpty);
      expect(doEntregador.quantidadeAguardandoEmissao, 1);

      final doLojista = PendenciasProvider(_Api(pendentes: [_pendente('tomador')]));
      await doLojista.carregar(fakeLojista());
      expect(doLojista.quantidadeNotas, 1);
      expect(doLojista.notasDoTurno(202), hasLength(1));
      expect(doLojista.quantidadeAguardandoEmissao, 0);
    });
  });
}

NotaFiscalPendente _pendente(String papel) => NotaFiscalPendente(
      turnoId: 202,
      prestadorId: 1,
      tituloTurno: 'Turno Noite — Hamburgueria',
      dataInicio: DateTime(2025, 8, 14, 18),
      valorServico: 120,
      contraparteNome: papel == 'prestador' ? 'Hamburgueria da Cláudia' : 'Ricardo Souza',
      papel: papel,
    );

/// O pagamento recebido do entregador — com a nota emitida ou não.
Transacao _recebido({required int? documentoId}) => Transacao(
      id: 92,
      motoboyId: 1,
      contraparteId: 2,
      turnoId: 202,
      tipo: TipoTransacao.pagamentoRecebido,
      natureza: NaturezaTransacao.credito,
      valor: 120,
      descricao: 'Turno finalizado: Hamburgueria da Cláudia',
      criadoEm: DateTime(2025, 8, 14, 22),
      // Como o backend responde: sem nota, o entregador não tem o que abrir.
      documentoDisponivel: documentoId != null,
      tipoDocumento: TipoDocumento.nfse,
      documentoId: documentoId,
    );

class _Api extends FakeApiService {
  _Api({List<NotaFiscalPendente> pendentes = const []})
      : notasFake = FakeNotaFiscalApi()..listaPendentes = pendentes;

  final FakeNotaFiscalApi notasFake;
  final FakeCarteiraApi carteiraFake = FakeCarteiraApi();

  @override
  NotaFiscalApi get notasFiscais => notasFake;

  @override
  CarteiraApi get carteira => carteiraFake;
}
