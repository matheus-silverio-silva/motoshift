// Goldens das telas do perfil LOJISTA:
// Dashboard, Publicar Turno, Turnos publicados, Turno Lojista,
// Agenda, Perfil, Dados Pessoais, "CNH e Veículo" (modo Endereço),
// Minhas Avaliações, Histórico.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/agenda/agenda_screen.dart';
import 'package:moto_shift/views/agendar_turno/agendar_turno_screen.dart';
import 'package:moto_shift/views/cnh_veiculo/cnh_veiculo_screen.dart';
import 'package:moto_shift/views/dados_pessoais/dados_pessoais_screen.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/historico_turnos/historico_turnos_screen.dart';
import 'package:moto_shift/views/minhas_avaliacoes/minhas_avaliacoes_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/turno_lojista/turno_lojista_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupGoldenTests();
  });

  testWidgets('DashboardLojistScreen', (tester) async {
    await pumpGolden(
      tester,
      child: const DashboardLojistScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(DashboardLojistScreen),
      matchesGoldenFile('goldens/dashboard_lojista_screen.png'),
    );
  });

  testWidgets('AgendarTurnoScreen', (tester) async {
    await pumpGolden(
      tester,
      child: const AgendarTurnoScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(AgendarTurnoScreen),
      matchesGoldenFile('goldens/agendar_turno_screen.png'),
    );
  });

  testWidgets('TurnosLojistaListaScreen', (tester) async {
    await pumpGolden(
      tester,
      child: const TurnosLojistaListaScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(TurnosLojistaListaScreen),
      matchesGoldenFile('goldens/turnos_lojista_lista_screen.png'),
    );
  }, skip: true); // Timer HTTP do retry de socket fica pendente após dispose

  testWidgets('TurnoLojistScreen', (tester) async {
    final turno = Turno(
      id: 301,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Tarde — Hamburgueria',
      descricao: 'Entregas na região do Água Verde',
      regiao: 'Água Verde, Curitiba',
      dataInicio: DateTime.now().add(const Duration(days: 1, hours: 14)),
      dataFim: DateTime.now().add(const Duration(days: 1, hours: 18)),
      valorEstimado: 120,
      raioEntregaKm: 8,
      status: StatusTurno.aceito,
    );
    await pumpGolden(
      tester,
      child: const TurnoLojistScreen(),
      tipoUsuario: TipoUsuario.lojista,
      argumentos: turno,
    );
    await expectLater(
      find.byType(TurnoLojistScreen),
      matchesGoldenFile('goldens/turno_lojista_screen.png'),
    );
  }, skip: true); // Timer HTTP do retry de socket fica pendente após dispose

  testWidgets('AgendaScreen (lojista)', (tester) async {
    await pumpGolden(
      tester,
      child: const AgendaScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(AgendaScreen),
      matchesGoldenFile('goldens/agenda_screen_lojista.png'),
    );
  });

  testWidgets('PerfilScreen (lojista)', (tester) async {
    await pumpGolden(
      tester,
      child: const PerfilScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(PerfilScreen),
      matchesGoldenFile('goldens/perfil_screen_lojista.png'),
    );
  });

  testWidgets('DadosPessoaisScreen (lojista)', (tester) async {
    await pumpGolden(
      tester,
      child: const DadosPessoaisScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(DadosPessoaisScreen),
      matchesGoldenFile('goldens/dados_pessoais_lojista.png'),
    );
  });

  testWidgets('CnhVeiculoScreen (lojista — modo Endereço)', (tester) async {
    await pumpGolden(
      tester,
      child: const CnhVeiculoScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(CnhVeiculoScreen),
      matchesGoldenFile('goldens/cnh_veiculo_lojista.png'),
    );
  });

  testWidgets('MinhasAvaliacoesScreen (lojista)', (tester) async {
    await pumpGolden(
      tester,
      child: const MinhasAvaliacoesScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(MinhasAvaliacoesScreen),
      matchesGoldenFile('goldens/minhas_avaliacoes_lojista.png'),
    );
  });

  testWidgets('HistoricoTurnosScreen (lojista)', (tester) async {
    await pumpGolden(
      tester,
      child: const HistoricoTurnosScreen(),
      tipoUsuario: TipoUsuario.lojista,
    );
    await expectLater(
      find.byType(HistoricoTurnosScreen),
      matchesGoldenFile('goldens/historico_turnos_lojista.png'),
    );
  }, skip: true); // Timer HTTP do retry de socket fica pendente após dispose
}
