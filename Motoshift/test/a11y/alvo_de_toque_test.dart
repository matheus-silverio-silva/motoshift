// Fase 5 pede "alvo de toque mínimo de 44px em tudo que é clicável".
//
// Isso estava declarado e nunca verificado. Este teste mede: monta as telas
// no viewport de celular, encontra tudo que responde a toque e confere a
// altura real do render box.
//
// 44 é o mínimo do guia da Apple; o Material pede 48. Ficamos no 44 porque é
// o número que o prompt da fase escolheu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/views/carteira/carteira_screen.dart';
import 'package:moto_shift/views/dashboard_lojista/dashboard_lojista_screen.dart';
import 'package:moto_shift/views/dashboard_motoboy/dashboard_motoboy_screen.dart';
import 'package:moto_shift/views/historico_turnos/historico_turnos_screen.dart';
import 'package:moto_shift/views/meus_turnos/meus_turnos_screen.dart';
import 'package:moto_shift/views/perfil/perfil_screen.dart';
import 'package:moto_shift/views/turnos_lojista_lista/turnos_lojista_lista_screen.dart';

import '../test_helpers.dart';

const double kAlvoMinimo = 44.0;

/// Um alvo pequeno demais, já formatado para a mensagem de falha.
class _AlvoPequeno {
  _AlvoPequeno(this.tipo, this.size, this.rotulo);
  final String tipo;
  final Size size;
  final String rotulo;

  @override
  String toString() =>
      '$tipo ${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}'
      '${rotulo.isEmpty ? '' : ' ("$rotulo")'}';
}

/// Texto dentro do alvo, para a falha dizer QUAL botão está pequeno.
String _rotuloDe(WidgetTester tester, Finder alvo) {
  final textos = find.descendant(of: alvo, matching: find.byType(Text));
  if (textos.evaluate().isEmpty) return '';
  final t = tester.widgetList<Text>(textos).first;
  return t.data ?? '';
}

/// Alvos de toque abaixo do mínimo, na tela já montada.
///
/// Só conta o que está visível: um alvo fora da viewport tem tamanho zero e
/// não é um defeito de layout.
List<_AlvoPequeno> _alvosPequenos(WidgetTester tester) {
  final pequenos = <_AlvoPequeno>[];

  void medir(Finder finder, String tipo) {
    for (var i = 0; i < finder.evaluate().length; i++) {
      final alvo = finder.at(i);
      final Size size;
      try {
        size = tester.getSize(alvo);
      } catch (_) {
        continue; // sem render box (fora da árvore renderizada)
      }
      if (size.isEmpty) continue;
      // Altura é o eixo que aperta: quase tudo aqui é largo e baixo.
      if (size.height < kAlvoMinimo) {
        pequenos.add(_AlvoPequeno(tipo, size, _rotuloDe(tester, alvo)));
      }
    }
  }

  // GestureDetector aninhado conta uma vez só por instância; InkWell interno
  // do Material já é coberto pelo widget que o hospeda.
  medir(find.byType(GestureDetector), 'GestureDetector');
  medir(find.byType(InkWell), 'InkWell');
  medir(find.byType(IconButton), 'IconButton');

  return pequenos;
}

void main() {
  setUpAll(setupGoldenTests);

  Future<List<_AlvoPequeno>> medirTela(
    WidgetTester tester,
    Widget tela, {
    TipoUsuario usuario = TipoUsuario.motoboy,
  }) async {
    await pumpGolden(
      tester,
      child: tela,
      tipoUsuario: usuario,
      viewport: const Size(390, 844),
    );
    return _alvosPequenos(tester);
  }

  testWidgets('dashboard do motoboy', (t) async {
    expect(
      await medirTela(t, DashboardMotoboyScreen(agora: dataAncoraGolden)),
      isEmpty,
    );
  });

  testWidgets('dashboard do lojista', (t) async {
    expect(
      await medirTela(t, DashboardLojistScreen(agora: dataAncoraGolden),
          usuario: TipoUsuario.lojista),
      isEmpty,
    );
  });

  testWidgets('turnos disponíveis', (t) async {
    expect(
      await medirTela(t, MeusTurnosScreen(agora: dataAncoraGolden)),
      isEmpty,
    );
  });

  testWidgets('turnos do lojista', (t) async {
    expect(
      await medirTela(t, const TurnosLojistaListaScreen(),
          usuario: TipoUsuario.lojista),
      isEmpty,
    );
  });

  testWidgets('histórico de turnos', (t) async {
    expect(
      await medirTela(t, const HistoricoTurnosScreen()),
      isEmpty,
    );
  });

  testWidgets('carteira', (t) async {
    expect(await medirTela(t, const CarteiraScreen()), isEmpty);
  });

  testWidgets('perfil', (t) async {
    expect(await medirTela(t, const PerfilScreen()), isEmpty);
  });
}
