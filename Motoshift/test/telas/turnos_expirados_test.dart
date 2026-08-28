// O status `expirado` (SCRUM-19) existia no backend e não existia na tela.
//
// O backend expira sozinho o turno que ninguém aceitou até o horário de
// início — e isso já aconteceu em produção. Só que o histórico filtrava
// `finalizado || cancelado` e a lista do lojista só tinha as abas "Abertos"
// (aberto|aceito) e "Finalizados". Resultado: o lojista publicava, ninguém
// aceitava, o backend expirava certo — e o turno sumia da interface. Não
// estava em "Abertos", nem em "Finalizados", nem no histórico.
//
// Estes testes prendem os dois lugares onde ele volta a aparecer.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/presentation/providers/notificacao_provider.dart';
import 'package:moto_shift/presentation/providers/turno_provider.dart';
import 'package:moto_shift/presentation/providers/turno_selecionado_provider.dart';
import 'package:moto_shift/services/api_service.dart';
import 'package:moto_shift/services/auth_service.dart';
import 'package:moto_shift/theme/app_theme.dart';
import 'package:moto_shift/views/historico_turnos/historico_turnos_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';
import 'package:moto_shift/widgets/shift_card.dart';

import '../test_helpers.dart';

const _mobile = Size(390, 844);

Turno turnoExpirado() {
  final hoje = hojeAncorado();
  return Turno(
    id: 999,
    lojistId: 2,
    titulo: 'Turno sem candidato',
    regiao: 'Batel, Curitiba',
    dataInicio: hoje.subtract(const Duration(days: 1, hours: -18)),
    dataFim: hoje.subtract(const Duration(days: 1, hours: -22)),
    valorEstimado: 150,
    raioEntregaKm: 5,
    status: StatusTurno.expirado,
  );
}

/// Mesma API fake da suíte, com um turno expirado a mais nas duas listagens.
class _ApiComExpirado extends FakeApiService {
  @override
  Future<List<Turno>> listarMeusTurnos(int motoboyId) async =>
      [...fakeMeusTurnos(), turnoExpirado()];

  @override
  Future<List<Turno>> listarTurnosLojista(int lojistId) async =>
      [...fakeTurnosLojista(), turnoExpirado()];
}

Future<void> _montar(
  WidgetTester tester, {
  required Widget tela,
  required TipoUsuario tipoUsuario,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _mobile;
  await tester.binding.setSurfaceSize(_mobile);

  final api = _ApiComExpirado();
  final usuario =
      tipoUsuario == TipoUsuario.lojista ? fakeLojista() : fakeMotoboy();
  final auth = AuthService(api)..atualizarUsuarioLocal(usuario);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<TurnoProvider>(create: (_) => TurnoProvider(api)),
        ChangeNotifierProvider<TurnoSelecionadoProvider>(
          create: (_) => TurnoSelecionadoProvider(),
        ),
        ChangeNotifierProvider<NotificacaoProvider>(
          create: (_) => NotificacaoProvider(api),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: tela,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

/// As pílulas de filtro rolam na horizontal: num viewport de 390px as
/// últimas nascem fora da tela e o `tap` erraria o alvo em silêncio.
Future<void> _tocarFiltro(WidgetTester tester, String rotulo) async {
  final alvo = find.text(rotulo);
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(setupGoldenTests);

  group('Histórico de turnos', () {
    testWidgets('lista o turno expirado — não só finalizado e cancelado',
        (tester) async {
      await _montar(
        tester,
        tela: const HistoricoTurnosScreen(),
        tipoUsuario: TipoUsuario.motoboy,
      );

      // A pílula do card é o rótulo do status: se caísse no ramo default do
      // histórico ele apareceria rotulado como "Finalizado".
      expect(find.text('Expirado'), findsOneWidget);
      expect(find.textContaining('Turno sem candidato'), findsOneWidget);
    });

    testWidgets('a aba "Expirados" isola só os expirados', (tester) async {
      await _montar(
        tester,
        tela: const HistoricoTurnosScreen(),
        tipoUsuario: TipoUsuario.motoboy,
      );

      await _tocarFiltro(tester, 'Expirados');

      expect(find.textContaining('Turno sem candidato'), findsOneWidget);
      expect(find.byType(ShiftCard), findsOneWidget);
    });

    testWidgets('a aba "Cancelados" não traz o expirado junto', (tester) async {
      await _montar(
        tester,
        tela: const HistoricoTurnosScreen(),
        tipoUsuario: TipoUsuario.motoboy,
      );

      await _tocarFiltro(tester, 'Cancelados');

      expect(find.textContaining('Turno sem candidato'), findsNothing);
    });
  });

  group('Lista de turnos do lojista', () {
    testWidgets('a aba "Expirados" existe e filtra', (tester) async {
      await _montar(
        tester,
        tela: const TurnosLojistaListaScreen(),
        tipoUsuario: TipoUsuario.lojista,
      );

      // Em "Todos" o expirado aparece com o rótulo certo.
      expect(find.text('Expirado'), findsOneWidget);

      await _tocarFiltro(tester, 'Expirados');

      expect(find.byType(ShiftCard), findsOneWidget);
      expect(find.textContaining('Turno sem candidato'), findsOneWidget);
    });

    testWidgets('o expirado não aparece em "Abertos" nem em "Finalizados"',
        (tester) async {
      await _montar(
        tester,
        tela: const TurnosLojistaListaScreen(),
        tipoUsuario: TipoUsuario.lojista,
      );

      await _tocarFiltro(tester, 'Abertos');
      expect(find.textContaining('Turno sem candidato'), findsNothing);

      await _tocarFiltro(tester, 'Finalizados');
      expect(find.textContaining('Turno sem candidato'), findsNothing);
    });
  });
}
