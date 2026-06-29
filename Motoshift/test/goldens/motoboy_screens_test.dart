// Goldens das telas do perfil MOTOBOY:
// Dashboard, Meus Turnos, Carteira, Agenda, Perfil, Dados Pessoais,
// CNH e Veículo, Minhas Avaliações, Histórico de Turnos, Detalhe Turno,
// Avaliação.

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_shift/models/turno.dart';
import 'package:moto_shift/views/agenda/agenda_screen.dart';
import 'package:moto_shift/views/avaliacao/avaliacao_screen.dart';
import 'package:moto_shift/views/carteira/carteira_screen.dart';
import 'package:moto_shift/views/cnh_veiculo/cnh_veiculo_screen.dart';
import 'package:moto_shift/views/dados_pessoais/dados_pessoais_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/detalhe_turno/detalhe_turno_screen.dart';
import 'package:moto_shift/views/historico_turnos/historico_turnos_screen.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/views/minhas_avaliacoes/minhas_avaliacoes_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupGoldenTests();
  });

  testWidgets('DashboardMotoboyScreen', (tester) async {
    await pumpGolden(tester, child: const DashboardMotoboyScreen());
    await expectLater(
      find.byType(DashboardMotoboyScreen),
      matchesGoldenFile('goldens/dashboard_motoboy_screen.png'),
    );
  });

  testWidgets('MeusTurnosScreen', (tester) async {
    await pumpGolden(tester, child: const MeusTurnosScreen());
    await expectLater(
      find.byType(MeusTurnosScreen),
      matchesGoldenFile('goldens/meus_turnos_screen.png'),
    );
  }, skip: true); // Timer HTTP do retry de socket fica pendente após dispose

  testWidgets('CarteiraScreen', (tester) async {
    await pumpGolden(tester, child: const CarteiraScreen());
    await expectLater(
      find.byType(CarteiraScreen),
      matchesGoldenFile('goldens/carteira_screen.png'),
    );
  });

  testWidgets('AgendaScreen (motoboy)', (tester) async {
    await pumpGolden(tester, child: const AgendaScreen());
    await expectLater(
      find.byType(AgendaScreen),
      matchesGoldenFile('goldens/agenda_screen_motoboy.png'),
    );
  });

  testWidgets('PerfilScreen (motoboy)', (tester) async {
    await pumpGolden(tester, child: const PerfilScreen());
    await expectLater(
      find.byType(PerfilScreen),
      matchesGoldenFile('goldens/perfil_screen_motoboy.png'),
    );
  });

  testWidgets('DadosPessoaisScreen (motoboy)', (tester) async {
    await pumpGolden(tester, child: const DadosPessoaisScreen());
    await expectLater(
      find.byType(DadosPessoaisScreen),
      matchesGoldenFile('goldens/dados_pessoais_motoboy.png'),
    );
  });

  testWidgets('CnhVeiculoScreen (motoboy)', (tester) async {
    await pumpGolden(tester, child: const CnhVeiculoScreen());
    await expectLater(
      find.byType(CnhVeiculoScreen),
      matchesGoldenFile('goldens/cnh_veiculo_motoboy.png'),
    );
  });

  testWidgets('MinhasAvaliacoesScreen (motoboy)', (tester) async {
    await pumpGolden(tester, child: const MinhasAvaliacoesScreen());
    await expectLater(
      find.byType(MinhasAvaliacoesScreen),
      matchesGoldenFile('goldens/minhas_avaliacoes_motoboy.png'),
    );
  });

  testWidgets('HistoricoTurnosScreen (motoboy)', (tester) async {
    await pumpGolden(tester, child: const HistoricoTurnosScreen());
    await expectLater(
      find.byType(HistoricoTurnosScreen),
      matchesGoldenFile('goldens/historico_turnos_motoboy.png'),
    );
  }, skip: true); // Timer HTTP do retry de socket fica pendente após dispose

  testWidgets('DetalheTurnoScreen', (tester) async {
    final turno = Turno(
      id: 999,
      lojistId: 2,
      motoboyId: 1,
      titulo: 'Turno Tarde — Hamburgueria',
      descricao: 'Entregas na região do Água Verde',
      regiao: 'Água Verde, Curitiba',
      dataInicio: DateTime.now().add(const Duration(days: 1, hours: 14)),
      dataFim: DateTime.now().add(const Duration(days: 1, hours: 18)),
      valorEstimado: 120,
      raioEntregaKm: 8,
    );
    await pumpGolden(
      tester,
      child: const DetalheTurnoScreen(),
      argumentos: turno,
    );
    await expectLater(
      find.byType(DetalheTurnoScreen),
      matchesGoldenFile('goldens/detalhe_turno_screen.png'),
    );
  });

  testWidgets('AvaliacaoScreen', (tester) async {
    const args = AvaliacaoArgs(
      turnoId: 202,
      avaliadorId: 1,
      avaliadoId: 2,
      nomeAvaliado: 'Cláudia Oliveira',
    );
    await pumpGolden(
      tester,
      child: const AvaliacaoScreen(),
      argumentos: args,
    );
    await expectLater(
      find.byType(AvaliacaoScreen),
      matchesGoldenFile('goldens/avaliacao_screen.png'),
    );
  });
}
