// Captura das telas da Fase 3 no desktop — conferência visual, fora da suíte.
//   flutter test test/dev_capture/fase3_capture_test.dart --update-goldens --dart-define=CAPTURE=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/agenda/agenda_screen.dart';
import 'package:moto_shift/views/agendar_turno/agendar_turno_screen.dart';
import 'package:moto_shift/views/avaliacao/avaliacao_screen.dart';
import 'package:moto_shift/views/carteira/carteira_screen.dart';
import 'package:moto_shift/views/cnh_veiculo/cnh_veiculo_screen.dart';
import 'package:moto_shift/views/dados_pessoais/dados_pessoais_screen.dart';
import 'package:moto_shift/views/historico_turnos/historico_turnos_screen.dart';
import 'package:moto_shift/views/minhas_avaliacoes/minhas_avaliacoes_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';

import '../test_helpers.dart';

const _capture = bool.fromEnvironment('CAPTURE');
const _desktop = Size(1440, 1024);

void main() {
  setUpAll(setupGoldenTests);

  Future<void> capturar(
    WidgetTester tester, {
    required Widget tela,
    required Type tipo,
    required String nome,
    TipoUsuario usuario = TipoUsuario.motoboy,
    Object? argumentos,
  }) async {
    await pumpGolden(
      tester,
      child: tela,
      tipoUsuario: usuario,
      viewport: _desktop,
      argumentos: argumentos,
    );
    await expectLater(
      find.byType(tipo),
      matchesGoldenFile('capturas/f3_$nome.png'),
    );
  }

  testWidgets('07 publicar turno', (t) async {
    await capturar(t,
        tela: const AgendarTurnoScreen(),
        tipo: AgendarTurnoScreen,
        nome: 'publicar_turno',
        usuario: TipoUsuario.lojista);
  }, skip: !_capture);

  testWidgets('09 agenda', (t) async {
    await capturar(t,
        tela: const AgendaScreen(),
        tipo: AgendaScreen,
        nome: 'agenda',
        usuario: TipoUsuario.lojista);
  }, skip: !_capture);

  testWidgets('10 carteira', (t) async {
    await capturar(t,
        tela: const CarteiraScreen(), tipo: CarteiraScreen, nome: 'carteira');
  }, skip: !_capture);

  testWidgets('11 historico', (t) async {
    await capturar(t,
        tela: const HistoricoTurnosScreen(),
        tipo: HistoricoTurnosScreen,
        nome: 'historico');
  }, skip: !_capture);

  testWidgets('12 avaliacao modal', (t) async {
    await capturar(
      t,
      tela: const AvaliacaoScreen(),
      tipo: AvaliacaoScreen,
      nome: 'avaliacao_modal',
      argumentos: const AvaliacaoArgs(
        turnoId: 202,
        avaliadorId: 1,
        avaliadoId: 2,
        nomeAvaliado: 'Cláudia Oliveira',
      ),
    );
  }, skip: !_capture);

  testWidgets('13 minhas avaliacoes', (t) async {
    await capturar(t,
        tela: const MinhasAvaliacoesScreen(),
        tipo: MinhasAvaliacoesScreen,
        nome: 'minhas_avaliacoes');
  }, skip: !_capture);

  testWidgets('14 perfil', (t) async {
    await capturar(t,
        tela: const PerfilScreen(), tipo: PerfilScreen, nome: 'perfil');
  }, skip: !_capture);

  // ── Sub-páginas do perfil ────────────────────────────────────────────────
  // Ficaram de fora da Fase 3 e eram as duas últimas telas roteadas sem shell
  // desktop: o Perfil é item de sidebar e leva a elas por pushNamed, então o
  // shell inteiro sumia no meio da navegação.

  testWidgets('15 dados pessoais (motoboy)', (t) async {
    await capturar(t,
        tela: const DadosPessoaisScreen(),
        tipo: DadosPessoaisScreen,
        nome: 'dados_pessoais_motoboy');
  }, skip: !_capture);

  testWidgets('15 dados pessoais (lojista)', (t) async {
    await capturar(t,
        tela: const DadosPessoaisScreen(),
        tipo: DadosPessoaisScreen,
        usuario: TipoUsuario.lojista,
        nome: 'dados_pessoais_lojista');
  }, skip: !_capture);

  testWidgets('16 cnh e veiculo (motoboy)', (t) async {
    await capturar(t,
        tela: const CnhVeiculoScreen(),
        tipo: CnhVeiculoScreen,
        nome: 'cnh_veiculo_motoboy');
  }, skip: !_capture);

  testWidgets('16 estabelecimento (lojista)', (t) async {
    await capturar(t,
        tela: const CnhVeiculoScreen(),
        tipo: CnhVeiculoScreen,
        usuario: TipoUsuario.lojista,
        nome: 'cnh_veiculo_lojista');
  }, skip: !_capture);
}
