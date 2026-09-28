import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/presenca.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/api_client.dart';
import 'package:moto_shift/services/api/dashboard_api.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/services/localizacao_service.dart';
import 'package:moto_shift/views/detalhe_turno/detalhe_turno_conteudo.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/turno_lojista/turno_lojista_conteudo.dart';
import 'package:moto_shift/widgets/acoes_do_turno.dart';

import '../localizacao/fonte_falsa.dart';
import '../test_helpers.dart';

/// Check-in e check-out no app (V16): o "Cheguei" do entregador, o que o
/// lojista vê, e a pontualidade de volta ao perfil.
void main() {
  setUpAll(setupGoldenTests);

  final gps = LocalizacaoService(fonte: FonteFalsa(lat: -25.4561, lng: -49.2821));

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Presenca (modelo)', () {
    test('chegada antes, no horário e depois do início', () {
      expect(const Presenca(minutosDoInicio: -3).relativoAoInicio, '3 min antes');
      expect(const Presenca(minutosDoInicio: 0).relativoAoInicio, 'no horário');
      expect(const Presenca(minutosDoInicio: 12).relativoAoInicio, '12 min depois');
    });

    test('o resumo junta chegada e saída', () {
      final p = Presenca.doInscrito({
        'checkinEm': '2026-09-28T14:03:00',
        'checkoutEm': '2026-09-28T18:02:00',
        'minutosDoInicio': -3,
      });
      expect(p.resumo, 'Chegou às 14:03 (3 min antes) · saiu às 18:02');
    });

    test('sem as chaves (colega de outra vaga), não há presença', () {
      final p = Presenca.doInscrito({'motoboyId': 9, 'nome': 'Lucas'});
      expect(p.chegou, isFalse);
      expect(p.resumo, isNull);
    });
  });

  group('"Cheguei" no detalhe do entregador', () {
    testWidgets('manda a posição do GPS e mostra a chegada', (tester) async {
      final api = _ApiDePresenca();
      await pumpGolden(tester,
          child: Scaffold(body: DetalheTurnoConteudo(turno: _turnoAceito())),
          apiFake: api,
          localizacao: gps);

      expect(find.byKey(const Key('acao-cheguei')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('acao-cheguei')));
      await tester.tap(find.byKey(const Key('acao-cheguei')));
      await esperar(tester);

      expect(api.turnosFalsos.checkins.single, (-25.4561, -49.2821));
      expect(find.text('Chegada registrada. Bom turno!'), findsOneWidget);
      expect(find.textContaining('Chegou às 14:03 (2 min antes)'), findsOneWidget);
      expect(find.byKey(const Key('acao-encerrar')), findsOneWidget);
    });

    testWidgets('longe do local, mostra a distância que o backend mediu', (tester) async {
      final api = _ApiDePresenca()
        ..turnosFalsos.recusa = const ApiException(422,
            'Você está a 1,2 km do local. O check-in é liberado a até 500 m do ponto do turno.');
      await pumpGolden(tester,
          child: Scaffold(body: DetalheTurnoConteudo(turno: _turnoAceito())),
          apiFake: api,
          localizacao: gps);

      await tester.ensureVisible(find.byKey(const Key('acao-cheguei')));
      await tester.tap(find.byKey(const Key('acao-cheguei')));
      await esperar(tester);

      expect(find.textContaining('Você está a 1,2 km do local'), findsOneWidget);
      expect(find.byKey(const Key('acao-cheguei')), findsOneWidget,
          reason: 'continua podendo tentar de novo');
    });

    testWidgets('sem GPS e com a trava ligada, a mensagem é a do GPS', (tester) async {
      final api = _ApiDePresenca()
        ..turnosFalsos.recusa =
            const ApiException(400, 'Envie a sua localização para fazer o check-in.');
      await pumpGolden(tester,
          child: Scaffold(body: DetalheTurnoConteudo(turno: _turnoAceito())),
          apiFake: api,
          localizacao: LocalizacaoService(fonte: FonteFalsa(ligado: false)));

      await tester.ensureVisible(find.byKey(const Key('acao-cheguei')));
      await tester.tap(find.byKey(const Key('acao-cheguei')));
      await esperar(tester);

      expect(find.text(FalhaLocalizacao.servicoDesligado.mensagem), findsOneWidget);
    });

    testWidgets('"Encerrar turno" pede confirmação e registra a saída', (tester) async {
      final api = _ApiDePresenca()..turnosFalsos.chegou = true;
      await pumpGolden(tester,
          child: Scaffold(body: DetalheTurnoConteudo(turno: _turnoAceito())),
          apiFake: api,
          localizacao: gps);

      await tester.ensureVisible(find.byKey(const Key('acao-encerrar')));
      await tester.tap(find.byKey(const Key('acao-encerrar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar-encerrar')));
      await esperar(tester);

      expect(api.turnosFalsos.checkouts, 1);
      expect(find.textContaining('saiu às 18:02'), findsOneWidget);
      expect(find.byKey(const Key('acao-encerrar')), findsNothing);
    });

    testWidgets('quem não está no turno não vê a presença', (tester) async {
      final api = _ApiDePresenca()..turnosFalsos.inscrito = false;
      await pumpGolden(tester,
          child: Scaffold(body: DetalheTurnoConteudo(turno: _turnoAceito())),
          apiFake: api,
          localizacao: gps);

      expect(find.byKey(const Key('presenca-do-turno')), findsNothing);
    });
  });

  group('lojista', () {
    testWidgets('vê a chegada e a saída de cada entregador', (tester) async {
      final api = _ApiDePresenca()
        ..turnosFalsos.chegou = true
        ..turnosFalsos.saiu = true;
      await pumpGolden(tester,
          child: Scaffold(body: TurnoLojistaConteudo(turno: _turnoAceito())),
          tipoUsuario: TipoUsuario.lojista,
          apiFake: api);

      // O card do entregador fica abaixo do mapa (e do "Adicionar ao
      // calendário"): numa lista preguiçosa, só existe depois de rolar.
      final presenca = find.text('Chegou às 14:03 (2 min antes) · saiu às 18:02');
      await tester.scrollUntilVisible(presenca, 200,
          scrollable: find.byType(Scrollable).first);
      expect(presenca, findsOneWidget);
      // O lojista não faz check-in.
      expect(find.byKey(const Key('acao-cheguei')), findsNothing);
    });

    testWidgets('turno em andamento não oferece "Cancelar turno"', (tester) async {
      await pumpGolden(tester,
          child: Scaffold(
              body: AcoesDoTurno(
                  turno: _turnoAceito(status: StatusTurno.emAndamento))),
          tipoUsuario: TipoUsuario.lojista);

      expect(find.byKey(const Key('acao-finalizar')), findsOneWidget);
      expect(find.byKey(const Key('acao-cancelar')), findsNothing);
    });
  });

  group('pontualidade no perfil', () {
    testWidgets('com check-ins, o percentual', (tester) async {
      await pumpGolden(tester, child: PerfilScreen(agora: dataAncoraGolden));
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('PONTUALIDADE'), findsOneWidget);
    });

    testWidgets('sem check-in, "Sem histórico" — nunca 100%', (tester) async {
      await pumpGolden(tester,
          child: PerfilScreen(agora: dataAncoraGolden), apiFake: _ApiSemPontualidade());
      expect(find.text('Sem histórico'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('o lojista não tem pontualidade', (tester) async {
      await pumpGolden(tester,
          child: PerfilScreen(agora: dataAncoraGolden), tipoUsuario: TipoUsuario.lojista);
      expect(find.text('PONTUALIDADE'), findsNothing);
    });
  });
}

/// Turno de 1 vaga do fake lojista (id 2), aceito pelo fake entregador (id 1),
/// começando às 14:05.
Turno _turnoAceito({StatusTurno status = StatusTurno.aceito}) {
  final hoje = DateTime.now();
  return Turno(
    id: 501,
    lojistId: 2,
    motoboyId: 1,
    titulo: 'Turno Tarde — Hamburgueria',
    regiao: 'Água Verde, Curitiba',
    dataInicio: DateTime(hoje.year, hoje.month, hoje.day, 14, 5),
    dataFim: DateTime(hoje.year, hoje.month, hoje.day, 18, 5),
    valorEstimado: 120,
    raioEntregaKm: 8,
    latitude: -25.4560,
    longitude: -49.2820,
    status: status,
  );
}

class _TurnosDePresenca extends FakeTurnoApi {
  bool inscrito = true;
  bool chegou = false;
  bool saiu = false;
  ApiException? recusa;
  final List<(double?, double?)> checkins = [];
  int checkouts = 0;

  @override
  Future<List<Map<String, dynamic>>> listarInscritos(int turnoId) async => [
        if (inscrito)
          {
            'motoboyId': 1,
            'nome': 'Ricardo Souza',
            'status': 'aceito',
            'pagamentoStatus': null,
            'checkinEm': chegou ? '2026-09-28T14:03:00' : null,
            'checkoutEm': saiu ? '2026-09-28T18:02:00' : null,
            'minutosDoInicio': chegou ? -2 : null,
          },
      ];

  @override
  Future<Turno> checkin(int turnoId, {double? latitude, double? longitude}) async {
    final r = recusa;
    if (r != null) throw r;
    checkins.add((latitude, longitude));
    chegou = true;
    return _turnoAceito(status: StatusTurno.emAndamento);
  }

  @override
  Future<Turno> checkout(int turnoId) async {
    checkouts++;
    saiu = true;
    return _turnoAceito(status: StatusTurno.emAndamento);
  }
}

class _ApiDePresenca extends FakeApiService {
  final _TurnosDePresenca turnosFalsos = _TurnosDePresenca();

  @override
  TurnoApi get turnos => turnosFalsos;
}

class _DashboardSemPontualidade extends FakeDashboardApi {
  @override
  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) async => {
        ...fakeDashboardMotoboy(),
        'pontualidade': null,
        'checkinsPontualidade': 0,
      };
}

class _ApiSemPontualidade extends FakeApiService {
  final DashboardApi _dash = _DashboardSemPontualidade();

  @override
  DashboardApi get dashboard => _dash;
}
