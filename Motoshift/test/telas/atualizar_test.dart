import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/services/api/agenda_api.dart';
import 'package:moto_shift/services/api/dashboard_api.dart';
import 'package:moto_shift/services/api/turno_api.dart';
import 'package:moto_shift/views/agenda/agenda_screen.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/detalhe_turno/detalhe_turno_screen.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/turno_lojista/turno_lojista_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';

import '../test_helpers.dart';

/// Telas que se atualizam (SCRUM-39).
///
/// As telas de turno só buscavam os dados ao abrir. Com a tela aberta, o que
/// muda é justamente o que está nela — um entregador aceita, faz check-in,
/// desiste; outro turno é publicado —, e a única saída era sair e voltar.
///
/// No celular: puxar para baixo (`RefreshIndicator`), que precisa funcionar
/// também com a lista curta — por isso o rolável é sempre rolável. No
/// desktop, onde não há o que puxar, o botão "Atualizar" da topbar.
void main() {
  setUpAll(setupGoldenTests);

  const celular = Size(390, 844);
  const desktop = Size(1440, 1024);

  /// Puxa o primeiro rolável vertical da tela para baixo, como o dedo faria.
  Future<void> puxar(WidgetTester tester) async {
    final lista = find
        .descendant(
            of: find.byKey(const Key('puxar-para-atualizar')),
            matching: find.byWidgetPredicate((w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down))
        .first;
    await tester.drag(lista, const Offset(0, 320));
    // O indicador desce, dispara o onRefresh e some.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  final telas = <({
    String nome,
    TipoUsuario papel,
    Widget Function() tela,
    int Function(_ApiQueConta) buscas,
  })>[
    (
      nome: 'painel do entregador',
      papel: TipoUsuario.motoboy,
      tela: () => DashboardMotoboyScreen(agora: dataAncoraGolden),
      buscas: (api) => api.painel.doMotoboy,
    ),
    (
      nome: 'painel do lojista',
      papel: TipoUsuario.lojista,
      tela: () => DashboardLojistScreen(agora: dataAncoraGolden),
      buscas: (api) => api.painel.doLojista,
    ),
    (
      nome: 'turnos do entregador (meus turnos e disponíveis)',
      papel: TipoUsuario.motoboy,
      tela: () => MeusTurnosScreen(agora: dataAncoraGolden),
      buscas: (api) => api.turnosFalsos.meus + api.turnosFalsos.disponiveis,
    ),
    (
      nome: 'turnos do lojista',
      papel: TipoUsuario.lojista,
      tela: () => const TurnosLojistaListaScreen(),
      buscas: (api) => api.turnosFalsos.doLojista,
    ),
    (
      nome: 'agenda',
      papel: TipoUsuario.motoboy,
      tela: () => AgendaScreen(agora: dataAncoraGolden),
      buscas: (api) => api.agendaFalsa.mensais,
    ),
  ];

  group('puxar para atualizar (celular)', () {
    for (final t in telas) {
      testWidgets('${t.nome}: puxar a lista busca os dados de novo',
          (tester) async {
        final api = _ApiQueConta(t.papel);
        await pumpGolden(tester,
            child: t.tela(),
            tipoUsuario: t.papel,
            apiFake: api,
            viewport: celular);
        final antes = t.buscas(api);
        expect(antes, greaterThan(0), reason: 'a tela carrega ao abrir');

        await puxar(tester);

        expect(t.buscas(api), greaterThan(antes));
      });
    }

    testWidgets('a lista é sempre rolável — o gesto vale mesmo com pouco conteúdo',
        (tester) async {
      for (final t in telas) {
        await pumpGolden(tester,
            child: t.tela(), tipoUsuario: t.papel, viewport: celular);
        final rolavel = tester.widget<Scrollable>(find
            .descendant(
                of: find.byKey(const Key('puxar-para-atualizar')),
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down))
            .first);
        expect(rolavel.physics, isA<AlwaysScrollableScrollPhysics>(),
            reason: t.nome);
      }
    });
  });

  group('"Atualizar" na topbar (desktop)', () {
    for (final t in telas) {
      testWidgets('${t.nome}: o botão busca os dados de novo', (tester) async {
        final api = _ApiQueConta(t.papel);
        await pumpGolden(tester,
            child: t.tela(),
            tipoUsuario: t.papel,
            apiFake: api,
            viewport: desktop);
        final antes = t.buscas(api);

        final botao = find.byKey(const Key('topbar-atualizar'));
        expect(botao, findsOneWidget);
        expect(find.byTooltip('Atualizar'), findsOneWidget);
        // No desktop não há gesto de puxar.
        expect(find.byKey(const Key('puxar-para-atualizar')), findsNothing);

        await tester.tap(botao);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(t.buscas(api), greaterThan(antes));
        // O botão volta a aceitar toque depois de recarregar.
        expect(find.byTooltip('Atualizar'), findsOneWidget);
      });
    }

    testWidgets('tela sem o que recarregar não ganha o botão', (tester) async {
      // O "atualizar" é opt-in da tela: a topbar não inventa um botão morto.
      await pumpGolden(tester,
          child: PerfilScreen(agora: dataAncoraGolden),
          tipoUsuario: TipoUsuario.lojista,
          viewport: desktop);
      expect(find.byKey(const Key('topbar-atualizar')), findsNothing);
    });
  });

  group('detalhe do turno', () {
    Turno aceito() => fakeTurnosLojista().first; // 301, aceito para amanhã

    testWidgets('entregador: puxar busca o turno de novo e mostra o que mudou',
        (tester) async {
      final api = _ApiQueConta(TipoUsuario.motoboy)
        ..turnosFalsos.statusAoBuscar = StatusTurno.cancelado;
      await pumpGolden(tester,
          child: const DetalheTurnoScreen(),
          argumentos: aceito(),
          apiFake: api,
          viewport: celular);
      expect(find.text('Turno cancelado'), findsNothing);

      await puxar(tester);

      expect(api.turnosFalsos.porId, [301]);
      // A loja cancelou enquanto a tela estava aberta: agora a tela diz.
      expect(find.text('Turno cancelado'), findsOneWidget);
    });

    testWidgets('lojista: puxar busca o turno e os inscritos de novo',
        (tester) async {
      final api = _ApiQueConta(TipoUsuario.lojista);
      await pumpGolden(tester,
          child: const TurnoLojistScreen(),
          argumentos: aceito(),
          tipoUsuario: TipoUsuario.lojista,
          apiFake: api,
          viewport: celular);
      final inscritosAntes = api.turnosFalsos.inscritos;
      expect(inscritosAntes, greaterThan(0));

      await puxar(tester);

      expect(api.turnosFalsos.porId, [301]);
      // É nos inscritos que aparece o "Chegou às 14:03".
      expect(api.turnosFalsos.inscritos, greaterThan(inscritosAntes));
    });
  });
}

// ── Fakes que contam as buscas// ── Fakes que contam as buscas ───────────────────────────────────────────────

class _TurnosQueContam extends FakeTurnoApi {
  int meus = 0;
  int disponiveis = 0;
  int doLojista = 0;
  int inscritos = 0;
  final List<int> porId = [];

  /// Se informado, o turno buscado por id volta com este status — é como o
  /// teste simula "mudou no backend enquanto a tela estava aberta".
  StatusTurno? statusAoBuscar;

  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) {
    meus++;
    return super.listarMeusTurnos(motoboyId);
  }

  @override
  Future<List<Turno>> listarTurnosDisponiveis({DateTime? data}) {
    disponiveis++;
    return super.listarTurnosDisponiveis(data: data);
  }

  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) {
    doLojista++;
    return super.listarTurnosLojista(lojistId);
  }

  @override
  Future<List<Map<String, dynamic>>> listarInscritos(int turnoId) {
    inscritos++;
    return super.listarInscritos(turnoId);
  }

  @override
  Future<Turno> buscarTurno(int turnoId) async {
    porId.add(turnoId);
    final t = await super.buscarTurno(turnoId);
    final status = statusAoBuscar;
    if (status == null) return t;
    return Turno(
      id: t.id,
      lojistId: t.lojistId,
      motoboyId: t.motoboyId,
      titulo: t.titulo,
      regiao: t.regiao,
      dataInicio: t.dataInicio,
      dataFim: t.dataFim,
      valorEstimado: t.valorEstimado,
      raioEntregaKm: t.raioEntregaKm,
      status: status,
    );
  }
}

class _PainelQueConta extends FakeDashboardApi {
  int doMotoboy = 0;
  int doLojista = 0;

  @override
  Future<Map<String, dynamic>> dashboardMotoboy(int motoboyId) {
    doMotoboy++;
    return super.dashboardMotoboy(motoboyId);
  }

  @override
  Future<Map<String, dynamic>> dashboardLojista(int lojistId) {
    doLojista++;
    return super.dashboardLojista(lojistId);
  }
}

class _AgendaQueConta extends FakeAgendaApi {
  int mensais = 0;

  @override
  Future<Map<String, dynamic>> buscarAgendaMensal(int usuarioId, int mes, int ano) {
    mensais++;
    return super.buscarAgendaMensal(usuarioId, mes, ano);
  }
}

class _ApiQueConta extends FakeApiService {
  _ApiQueConta(TipoUsuario papel) : super(tipoUsuario: papel);

  final _TurnosQueContam turnosFalsos = _TurnosQueContam();
  final _PainelQueConta painel = _PainelQueConta();
  final _AgendaQueConta agendaFalsa = _AgendaQueConta();

  @override
  TurnoApi get turnos => turnosFalsos;

  @override
  DashboardApi get dashboard => painel;

  @override
  AgendaApi get agenda => agendaFalsa;
}
