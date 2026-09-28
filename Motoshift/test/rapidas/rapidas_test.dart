import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/notificacao.dart';
import 'package:moto_shift/models/perfil_publico.dart';
import 'package:moto_shift/models/selo.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/services/abrir_rota.dart';
import 'package:moto_shift/services/api/auth_api.dart';
import 'package:moto_shift/services/api/dashboard_api.dart';
import 'package:moto_shift/services/api/usuario_api.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/perfil_publico/perfil_publico_screen.dart';
import 'package:moto_shift/widgets/atalhos_do_turno.dart';
import 'package:moto_shift/widgets/meta_do_mes.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// Fase 7: abrir rota, calendário, lembrete, meta do mês e selos.
void main() {
  setUpAll(setupGoldenTests);

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Turno turno({int id = 201, StatusTurno status = StatusTurno.aceito, bool ponto = true}) =>
      Turno(
        id: id,
        lojistId: 2,
        motoboyId: 1,
        titulo: 'Turno Noite — Hamburgueria',
        regiao: 'Água Verde, Curitiba',
        dataInicio: hojeAncorado().add(const Duration(days: 1, hours: 18)),
        dataFim: hojeAncorado().add(const Duration(days: 1, hours: 22)),
        valorEstimado: 130,
        raioEntregaKm: 8,
        latitude: ponto ? -25.456 : null,
        longitude: ponto ? -49.282 : null,
        status: status,
      );

  /// Monta os atalhos com os turnos do entregador já carregados (o 201 é
  /// dele — ver fakeMeusTurnos) e um navegador de mentira.
  Future<_NavegadorFalso> montar(WidgetTester tester, Turno t,
      {TipoUsuario tipo = TipoUsuario.motoboy, bool waze = false, bool web = false}) async {
    final nav = _NavegadorFalso(waze: waze, web: web);
    await pumpGolden(tester,
        tipoUsuario: tipo,
        child: Provider<AbrirRota>.value(
          value: AbrirRota(navegador: nav),
          child: Scaffold(body: AtalhosDoTurno(turno: t)),
        ));
    final ctx = tester.element(find.byType(Scaffold).first);
    await ctx.read<TurnoProvider>().carregarMeusTurnos(1);
    await tester.pump();
    return nav;
  }

  group('Abrir rota', () {
    testWidgets('no navegador, abre o Google Maps direto no ponto do turno',
        (tester) async {
      final nav = await montar(tester, turno(), web: true);
      await tester.tap(find.byKey(const Key('atalho-rota')));
      await esperar(tester);

      expect(nav.abertos.single.host, 'www.google.com');
      expect(nav.abertos.single.queryParameters['destination'], '-25.456,-49.282');
    });

    testWidgets('no celular com Waze instalado, a pessoa escolhe', (tester) async {
      final nav = await montar(tester, turno(), waze: true);
      await tester.tap(find.byKey(const Key('atalho-rota')));
      await esperar(tester);

      expect(find.text('Google Maps'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rota-waze')));
      await esperar(tester);
      expect(nav.abertos.single.host, 'waze.com');
      expect(nav.abertos.single.queryParameters['ll'], '-25.456,-49.282');
    });

    testWidgets('sem Waze, vai direto ao Google Maps; se não abrir, avisa',
        (tester) async {
      final nav = await montar(tester, turno())..falhar = true;
      await tester.tap(find.byKey(const Key('atalho-rota')));
      await esperar(tester);
      expect(find.text('Waze'), findsNothing);
      expect(nav.abertos, hasLength(1));
      expect(find.text('Não foi possível abrir o mapa.'), findsOneWidget);
    });

    testWidgets('turno sem ponto, ou já encerrado, não tem rota', (tester) async {
      await montar(tester, turno(ponto: false));
      expect(find.byKey(const Key('atalho-rota')), findsNothing);
    });
  });

  group('Adicionar ao calendário', () {
    testWidgets('o entregador do turno baixa o .ics pelo baixarArquivo', (tester) async {
      final baixados = fingirDownload();
      await montar(tester, turno());
      await tester.tap(find.byKey(const Key('atalho-calendario')));
      await esperar(tester);

      final arq = baixados.single;
      expect(arq.mime, 'text/calendar');
      expect(arq.nome, endsWith('.ics'));
      expect(String.fromCharCodes(arq.bytes), contains('BEGIN:VEVENT'));
      expect(find.textContaining('pronto — abra o arquivo'), findsOneWidget);
    });

    testWidgets('quem não está no turno não tem calendário (só a rota)',
        (tester) async {
      await montar(tester, turno(id: 999));
      expect(find.byKey(const Key('atalho-calendario')), findsNothing);
      expect(find.byKey(const Key('atalho-rota')), findsOneWidget);
    });

    testWidgets('a loja tem calendário do turno que publicou, e não tem rota',
        (tester) async {
      await montar(tester, turno(), tipo: TipoUsuario.lojista);
      expect(find.byKey(const Key('atalho-calendario')), findsOneWidget);
      expect(find.byKey(const Key('atalho-rota')), findsNothing);
      expect(find.text('Adicionar ao calendário'), findsOneWidget);
    });

    testWidgets('turno finalizado: nenhum atalho', (tester) async {
      await montar(tester, turno(status: StatusTurno.finalizado));
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  test('o lembrete de turno tem estilo próprio e abre o turno', () {
    final n = Notificacao.fromJson({
      'id': 1,
      'tipo': 'turno_lembrete',
      'titulo': 'Seu turno começa em breve',
      'mensagem': '"Turno Noite" na Hamburgueria da Cláudia começa às 18:00 — daqui a 45 min.',
      'lida': false,
      'referenciaTipo': 'turno',
      'referenciaId': 9,
      'criadoEm': '2026-09-28T17:15:00',
    });
    expect(n.estilo.icone, Icons.alarm_rounded);
    expect(n.referenciaTipo, 'turno');
  });

  group('Meta do mês', () {
    testWidgets('"R\$ 1.340 de R\$ 2.000 (67%)"', (tester) async {
      await pumpGolden(tester,
          child: Scaffold(
              body: MetaDoMes(ganhos: 1340, meta: 2000, onEditar: () {})));
      expect(find.text('R\$ 1.340 de R\$ 2.000 (67%)'), findsOneWidget);
      expect(
          tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
          closeTo(0.67, 0.001));
      expect(find.textContaining('Faltam R\$ 660'), findsOneWidget);
    });

    testWidgets('sem meta: convite, nunca uma barra zerada', (tester) async {
      await pumpGolden(tester,
          child: Scaffold(body: MetaDoMes(ganhos: 0, meta: null, onEditar: () {})));
      expect(find.byKey(const Key('meta-convite')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('meta batida: a barra para em 100%', (tester) async {
      await pumpGolden(tester,
          child: Scaffold(body: MetaDoMes(ganhos: 2500, meta: 2000, onEditar: () {})));
      expect(find.text('R\$ 2.500 de R\$ 2.000 (125%)'), findsOneWidget);
      expect(
          tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
          1.0);
      expect(find.textContaining('Meta batida'), findsOneWidget);
    });

    testWidgets('o entregador define a meta pelo painel, e ela vai ao perfil',
        (tester) async {
      final api = _ApiDaMeta();
      await pumpGolden(tester,
          child: const DashboardMotoboyScreen(), apiFake: api);
      await esperar(tester);

      await tester.ensureVisible(find.byKey(const Key('meta-definir')));
      await tester.tap(find.byKey(const Key('meta-definir')));
      await esperar(tester);
      await tester.enterText(find.byKey(const Key('meta-valor')), '2000');
      await tester.tap(find.byKey(const Key('meta-salvar')));
      await esperar(tester);

      expect(api.authFalsa.campos, {'metaMensal': 2000.0});
    });

    testWidgets('meta fora do intervalo não sai do diálogo', (tester) async {
      final api = _ApiDaMeta();
      await pumpGolden(tester,
          child: const DashboardMotoboyScreen(), apiFake: api);
      await esperar(tester);

      await tester.ensureVisible(find.byKey(const Key('meta-definir')));
      await tester.tap(find.byKey(const Key('meta-definir')));
      await esperar(tester);
      await tester.enterText(find.byKey(const Key('meta-valor')), '0');
      await tester.tap(find.byKey(const Key('meta-salvar')));
      await esperar(tester);

      expect(find.textContaining('entre R\$ 1 e R\$ 100.000'), findsOneWidget);
      expect(api.authFalsa.campos, isNull);
    });

    testWidgets('no perfil, a linha "Meta do mês" só existe para o entregador',
        (tester) async {
      await pumpGolden(tester,
          child: const PerfilScreen(),
          usuario: fakeMotoboy().copyWith(metaMensal: 2000));
      await esperar(tester);
      expect(find.byKey(const Key('perfil-meta')), findsOneWidget);
      expect(find.text('R\$ 2.000'), findsOneWidget);
    });
  });

  group('Selos de reputação', () {
    const selos = [
      {'codigo': 'pontual', 'titulo': 'Pontual', 'criterio': 'Chegou até 10 min depois do início em 90%.'},
      {'codigo': 'nota_alta', 'titulo': 'Nota acima de 4,8', 'criterio': 'Média acima de 4,8 em 10 avaliações ou mais.'},
    ];

    test('vêm no perfil público, e a falta deles é lista vazia', () {
      final base = {'id': 1, 'nome': 'Ricardo', 'tipo': 'motoboy'};
      expect(PerfilPublico.fromJson(base).selos, isEmpty);
      expect(PerfilPublico.fromJson({...base, 'selos': selos}).selos.map((s) => s.codigo),
          ['pontual', 'nota_alta']);
      expect(Selo.listaDe(null), isEmpty);
    });

    testWidgets('perfil público: os selos, e o critério ao tocar', (tester) async {
      await pumpGolden(tester,
          child: const PerfilPublicoScreen(),
          tipoUsuario: TipoUsuario.lojista,
          argumentos: const PerfilPublicoArgs(usuarioId: 1, nome: 'Ricardo Souza'),
          apiFake: _ApiComSelos());
      await esperar(tester);

      expect(find.byKey(const Key('selo-pontual')), findsOneWidget);
      await tester.tap(find.byKey(const Key('selo-pontual')));
      await esperar(tester);
      expect(find.text('Chegou até 10 min depois do início em 90%.'), findsOneWidget);
    });

    testWidgets('perfil próprio: os selos do painel', (tester) async {
      await pumpGolden(tester, child: const PerfilScreen(), apiFake: _ApiComSelos());
      await esperar(tester);
      expect(find.byKey(const Key('selo-nota_alta')), findsOneWidget);
    });

    testWidgets('sem selo, nada aparece', (tester) async {
      await pumpGolden(tester, child: const PerfilScreen());
      await esperar(tester);
      expect(find.byKey(const Key('selos-de-reputacao')), findsNothing);
    });
  });
}

// ── apoio ────────────────────────────────────────────────────────────────────

class _NavegadorFalso implements Navegador {
  _NavegadorFalso({this.waze = false, this.web = false});

  final bool waze;
  final bool web;
  bool falhar = false;
  final List<Uri> abertos = [];

  @override
  Future<bool> abrir(Uri uri) async {
    abertos.add(uri);
    return !falhar;
  }

  @override
  Future<bool> consegueAbrir(Uri uri) async => waze && uri.scheme == 'waze';

  @override
  bool get ehWeb => web;
}

class _AuthQueGrava extends FakeAuthApi {
  Map<String, dynamic>? campos;

  @override
  Future<Usuario> atualizarPerfil(int id, Map<String, dynamic> campos) async {
    this.campos = campos;
    return fakeMotoboy()
        .copyWith(metaMensal: (campos['metaMensal'] as num?)?.toDouble());
  }
}

class _ApiDaMeta extends FakeApiService {
  final _AuthQueGrava authFalsa = _AuthQueGrava();

  @override
  AuthApi get auth => authFalsa;
}

const _selosJson = [
  {'codigo': 'pontual', 'titulo': 'Pontual', 'criterio': 'Chegou até 10 min depois do início em 90%.'},
  {'codigo': 'nota_alta', 'titulo': 'Nota acima de 4,8', 'criterio': 'Média acima de 4,8 em 10 avaliações ou mais.'},
];

class _UsuariosComSelos extends FakeUsuarioApi {
  @override
  Future<PerfilPublico> buscarPerfilPublico(int usuarioId) async =>
      PerfilPublico.fromJson({
        'id': usuarioId,
        'nome': 'Ricardo Souza',
        'tipo': 'motoboy',
        'selos': _selosJson,
      });
}

class _DashboardComSelos extends FakeDashboardApi {
  @override
  Future<Map<String, dynamic>> dashboardMotoboy(int id) async =>
      {...fakeDashboardMotoboy(), 'selos': _selosJson};
}

class _ApiComSelos extends FakeApiService {
  @override
  UsuarioApi get usuarios => _UsuariosComSelos();

  @override
  DashboardApi get dashboard => _DashboardComSelos();
}
