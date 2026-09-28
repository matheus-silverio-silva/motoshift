import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_shift/models/repeticao_de_turno.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/services/localizacao_service.dart';
import 'package:moto_shift/views/agendar_turno/agendar_turno_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';
import 'package:moto_shift/widgets/acoes_do_turno.dart';
import 'package:moto_shift/widgets/mapa_raio.dart';

import '../localizacao/fonte_falsa.dart';
import '../test_helpers.dart';

/// "Publicar de novo": o turno que acabou vira o rascunho do próximo — e nada
/// é publicado sem passar pela confirmação do custo.
void main() {
  setUpAll(setupGoldenTests);

  // Sexta-feira, 18:00–22:00, numa semana qualquer.
  final sexta = DateTime(2026, 9, 18, 18);
  Turno origem({
    StatusTurno status = StatusTurno.finalizado,
    String titulo = 'Turno Noite — Hamburgueria da Cláudia',
    DateTime? inicio,
  }) {
    final i = inicio ?? sexta;
    return Turno(
      id: 77,
      lojistId: 2,
      motoboyId: 1,
      titulo: titulo,
      descricao: 'Entregas noturnas',
      regiao: 'Água Verde, Curitiba',
      endereco: 'Av. Água Verde, 1200 — Água Verde, Curitiba/PR',
      dataInicio: i,
      dataFim: i.add(const Duration(hours: 4)),
      valorEstimado: 130,
      raioEntregaKm: 8,
      latitude: -25.4560,
      longitude: -49.2820,
      vagas: 2,
      status: status,
    );
  }

  group('a data do turno repetido', () {
    test('turno da semana passada: mesma sexta, uma semana depois, mesmo horário',
        () {
      final r = RepeticaoDeTurno.de(origem(),
          agora: DateTime(2026, 9, 20, 10)); // domingo depois do turno
      expect(r.inicio, DateTime(2026, 9, 25, 18));
      expect(r.inicio.weekday, DateTime.friday);
      expect(r.fim, DateTime(2026, 9, 25, 22), reason: 'a duração não muda');
      expect(r.dataPorExtenso, 'sexta-feira, 25/09');
    });

    test('turno antigo: a primeira sexta que ainda dá para publicar', () {
      final r = RepeticaoDeTurno.de(origem(), agora: DateTime(2026, 11, 3, 9));
      expect(r.inicio, DateTime(2026, 11, 6, 18));
      expect(r.inicio.weekday, DateTime.friday);
    });

    test('a semana seguinte dentro das 2 h de antecedência pula mais uma', () {
      // Sexta, 16:30 da semana seguinte: faltam 1h30 para as 18:00.
      final r = RepeticaoDeTurno.de(origem(), agora: DateTime(2026, 9, 25, 16, 30));
      expect(r.inicio, DateTime(2026, 10, 2, 18));
    });

    test('turno cancelado antes de acontecer vai para a semana seguinte à dele',
        () {
      final futuro = origem(
          status: StatusTurno.cancelado, inicio: DateTime(2026, 10, 2, 18));
      final r = RepeticaoDeTurno.de(futuro, agora: DateTime(2026, 9, 28, 9));
      expect(r.inicio, DateTime(2026, 10, 9, 18));
    });

    test('título escrito pelo lojista fica; o automático é refeito pela data', () {
      final agora = DateTime(2026, 9, 20);
      expect(RepeticaoDeTurno.de(origem(), agora: agora).titulo,
          'Turno Noite — Hamburgueria da Cláudia');
      expect(
          RepeticaoDeTurno.de(origem(titulo: 'Turno 18/09'), agora: agora).titulo,
          isNull);
    });

    test('só finalizado, cancelado e expirado se repetem', () {
      for (final s in StatusTurno.values) {
        final esperado = s == StatusTurno.finalizado ||
            s == StatusTurno.cancelado ||
            s == StatusTurno.expirado;
        expect(RepeticaoDeTurno.podeRepetir(origem(status: s)), esperado,
            reason: s.name);
      }
    });
  });

  group('o formulário preenchido', () {
    testWidgets('traz tudo do turno de origem e publica só depois da confirmação',
        (tester) async {
      final fonte = FonteFalsa(lat: -23.55, lng: -46.63);
      final api = _ApiQueGrava();
      // Relativa ao relógio: a origem terminou há três dias.
      final inicioOrigem = DateTime(clock.now().year, clock.now().month,
          clock.now().day - 3, 18);
      final t = origem(inicio: inicioOrigem);
      final esperado = RepeticaoDeTurno.de(t);

      await pumpGolden(
        tester,
        child: AgendarTurnoScreen(origem: t),
        tipoUsuario: TipoUsuario.lojista,
        apiFake: api,
        localizacao: LocalizacaoService(fonte: fonte),
      );

      expect(find.text('Publicar de novo'), findsOneWidget);
      expect(find.byKey(const Key('aviso-repeticao')), findsOneWidget);
      expect(find.textContaining(esperado.dataPorExtenso), findsOneWidget);
      expect(find.text('130,00'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Água Verde, Curitiba'),
          findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: 'duas vagas');

      // O ponto é o do turno — o GPS, bem longe, nem é consultado.
      final mapa = tester.widget<MapaRaio>(find.byType(MapaRaio).first);
      expect(mapa.centro, const LatLng(-25.4560, -49.2820));
      expect(mapa.raioKm, 8);
      expect(fonte.chamadasDePosicao, 0);

      // Publicar abre a confirmação do custo — e nada vai para o backend
      // antes dela.
      final botao = find.text('Publicar Turno');
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await _esperar(tester);
      expect(find.text('Confirmar publicação'), findsOneWidget);
      expect(find.text('R\$ 260,00'), findsOneWidget,
          reason: 'R\$ 130 × 2 vagas');
      expect(api.gravados.turnos, isEmpty);

      await tester.tap(find.byKey(const Key('publicar-confirmar')));
      await _esperar(tester);

      final novo = api.gravados.turnos.single;
      expect(novo.titulo, 'Turno Noite — Hamburgueria da Cláudia');
      expect(novo.descricao, 'Entregas noturnas');
      expect(novo.regiao, 'Água Verde, Curitiba');
      expect(novo.endereco, 'Av. Água Verde, 1200 — Água Verde, Curitiba/PR');
      expect(novo.latitude, -25.4560);
      expect(novo.longitude, -49.2820);
      expect(novo.raioEntregaKm, 8);
      expect(novo.valorEstimado, 130);
      expect(novo.vagas, 2);
      expect(novo.dataInicio, esperado.inicio);
      expect(novo.dataFim.difference(novo.dataInicio), const Duration(hours: 4));
    });

    testWidgets('cancelar a confirmação não publica', (tester) async {
      final api = _ApiQueGrava();
      await pumpGolden(
        tester,
        child: AgendarTurnoScreen(origem: origem()),
        tipoUsuario: TipoUsuario.lojista,
        apiFake: api,
        localizacao: LocalizacaoService(fonte: FonteFalsa()),
      );
      final botao = find.text('Publicar Turno');
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await _esperar(tester);
      await tester.tap(find.text('Cancelar'));
      await _esperar(tester);
      expect(api.gravados.turnos, isEmpty);
    });

    testWidgets('a origem também chega pelos argumentos da rota', (tester) async {
      await pumpGolden(
        tester,
        child: const AgendarTurnoScreen(),
        tipoUsuario: TipoUsuario.lojista,
        argumentos: origem(),
        localizacao: LocalizacaoService(fonte: FonteFalsa()),
      );
      expect(find.byKey(const Key('aviso-repeticao')), findsOneWidget);
      expect(find.text('130,00'), findsOneWidget);
    });

    testWidgets('sem origem, o formulário continua em branco', (tester) async {
      await pumpGolden(
        tester,
        child: const AgendarTurnoScreen(),
        tipoUsuario: TipoUsuario.lojista,
        localizacao: LocalizacaoService(fonte: FonteFalsa()),
      );
      expect(find.text('Novo turno'), findsOneWidget);
      expect(find.byKey(const Key('aviso-repeticao')), findsNothing);
    });
  });

  group('o botão', () {
    for (final status in [
      StatusTurno.finalizado,
      StatusTurno.cancelado,
      StatusTurno.expirado,
    ]) {
      testWidgets('aparece no detalhe do turno ${status.name} do lojista',
          (tester) async {
        await pumpGolden(
          tester,
          child: Scaffold(body: AcoesDoTurno(turno: origem(status: status))),
          tipoUsuario: TipoUsuario.lojista,
        );
        expect(find.byKey(const Key('acao-publicar-de-novo')), findsOneWidget);

        await tester.tap(find.byKey(const Key('acao-publicar-de-novo')));
        await tester.pumpAndSettle();
        final rota = _rotaAtual(tester);
        expect(rota.name, AppRoutes.publicarTurno);
        expect((rota.arguments as Turno).id, 77);
      });
    }

    for (final status in [
      StatusTurno.aberto,
      StatusTurno.aceito,
      StatusTurno.emAndamento,
    ]) {
      testWidgets('não aparece no turno ${status.name}', (tester) async {
        await pumpGolden(
          tester,
          child: Scaffold(body: AcoesDoTurno(turno: origem(status: status))),
          tipoUsuario: TipoUsuario.lojista,
        );
        expect(find.byKey(const Key('acao-publicar-de-novo')), findsNothing);
      });
    }

    testWidgets('o entregador não publica turno', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(body: AcoesDoTurno(turno: origem())),
        tipoUsuario: TipoUsuario.motoboy,
      );
      expect(find.byKey(const Key('acao-publicar-de-novo')), findsNothing);
    });

    testWidgets('na lista, só nos cards de turno que já acabou', (tester) async {
      await pumpGolden(
        tester,
        child: const TurnosLojistaListaScreen(),
        tipoUsuario: TipoUsuario.lojista,
      );
      // fakeTurnosLojista: 301 aceito, 302 aberto, 303 finalizado.
      expect(find.byKey(const Key('repetir-303')), findsOneWidget);
      expect(find.byKey(const Key('repetir-301')), findsNothing);
      expect(find.byKey(const Key('repetir-302')), findsNothing);

      await tester.tap(find.byKey(const Key('repetir-303')));
      await tester.pumpAndSettle();
      final rota = _rotaAtual(tester);
      expect(rota.name, AppRoutes.publicarTurno);
      expect((rota.arguments as Turno).id, 303);
    });
  });
}

// ── apoio ────────────────────────────────────────────────────────────────────

/// A rota de cima: o `pumpGolden` manda toda navegação para uma página em
/// branco, que guarda o nome e os argumentos.
RouteSettings _rotaAtual(WidgetTester tester) {
  final pagina = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_BlankPage');
  return ModalRoute.of(tester.element(pagina))!.settings;
}

Future<void> _esperar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class _TurnosGravados extends FakeTurnoApi {
  final List<Turno> turnos = [];

  @override
  Future<Turno> criarTurno(Turno turno) async {
    turnos.add(turno);
    return turno;
  }
}

class _ApiQueGrava extends FakeApiService {
  _ApiQueGrava() : super(tipoUsuario: TipoUsuario.lojista);

  final _TurnosGravados gravados = _TurnosGravados();

  @override
  TurnoApi get turnos => gravados;
}
