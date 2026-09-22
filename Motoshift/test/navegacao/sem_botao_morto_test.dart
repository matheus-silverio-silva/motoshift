// Varredura de botões mortos (B7).
//
// Três jeitos de um botão prometer um destino e não entregar, todos
// encontrados nesta revisão:
//
//   * handler vazio — o "Contatar" do detalhe do turno era `onTap: () {}`;
//   * destino que é um aviso de "Em breve" — "Esqueci minha senha" levava a
//     um capacete de obra;
//   * rota que não existe na tabela — o `pushNamed` falha em tempo de
//     execução, na mão do usuário, e não em compilação.
//
// Os três são detectáveis lendo o código, então este teste lê.
//
// `lib/dev/` fica de fora de propósito: é a vitrine de layout usada para
// capturar o shell desktop (shell_preview_main.dart), não entra no app
// publicado, e o botão dela não tem para onde ir porque não há app em volta.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/app.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/app_routes.dart';
import 'package:moto_shift/routes/nav_config.dart';

Map<String, String> _fontes() => {
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/dev/')))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
    };

/// Linha (1-based) de uma posição no texto — para a mensagem apontar o lugar.
int _linha(String texto, int posicao) =>
    '\n'.allMatches(texto.substring(0, posicao)).length + 1;

/// Tira comentários de linha, para um exemplo citado num doc comment não
/// contar como botão morto.
String _semComentarios(String fonte) =>
    fonte.replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final fontes = _fontes();

  test('nenhum handler de toque é vazio', () {
    // `() {}`, `() => {}` e `() => null` — este último é um Map/nulo
    // disfarçado de ação, e o botão aparece habilitado sem fazer nada.
    // `onPressed: null` (sem lambda) é o jeito certo de desabilitar e não
    // entra aqui.
    final vazio = RegExp(
      r'on(Tap|Pressed|LongPress|DoubleTap)\s*:\s*\(\s*\)\s*'
      r'(\{\s*\}|=>\s*\{\s*\}|=>\s*null\b)',
    );
    final achados = [
      for (final e in fontes.entries)
        for (final m in vazio.allMatches(_semComentarios(e.value)))
          '${e.key}:${_linha(_semComentarios(e.value), m.start)}  ${m[0]}',
    ];
    expect(achados, isEmpty);
  });

  test('nenhuma tela diz "em breve"', () {
    // Um destino que só avisa que o destino não existe é um botão morto com
    // uma escala a mais.
    final emBreve = RegExp(r"'[^'\n]*\bem breve\b[^'\n]*'", caseSensitive: false);
    final achados = [
      for (final e in fontes.entries)
        for (final m in emBreve.allMatches(_semComentarios(e.value)))
          '${e.key}:${_linha(_semComentarios(e.value), m.start)}  ${m[0]}',
    ];
    expect(achados, isEmpty);
  });

  test('toda rota citada no código está registrada em rotasDoApp()', () {
    final fonteRotas = File('lib/routes/app_routes.dart').readAsStringSync();
    final valores = {
      for (final m in RegExp(r"static const String (\w+)\s*=\s*'([^']+)'")
          .allMatches(fonteRotas))
        m[1]!: m[2]!,
    };
    final registradas = rotasDoApp().keys.toSet();

    final uso = RegExp(r'AppRoutes\.(\w+)');
    final faltando = <String>{};
    for (final e in fontes.entries) {
      if (e.key.endsWith('lib/routes/app_routes.dart')) continue;
      for (final m in uso.allMatches(_semComentarios(e.value))) {
        final caminho = valores[m[1]!];
        if (caminho == null) continue; // método ou getter de AppRoutes
        if (!registradas.contains(caminho)) {
          faltando.add('${e.key}: AppRoutes.${m[1]} ($caminho)');
        }
      }
    }
    expect(faltando, isEmpty,
        reason: 'um pushNamed para rota não registrada falha na mão do '
            'usuário, não na compilação');
  });

  test('toda rota registrada é alcançável por algum lugar do app', () {
    // O inverso do teste anterior: tela registrada que nada abre. Foi o caso
    // de /avaliar-entregadores, que existia sem nenhum botão até ela, e do
    // extrato completo, que tinha filtros e exportação e nenhuma entrada.
    //
    // Conta como entrada: item de menu, ou `AppRoutes.x` citado numa tela,
    // num widget ou numa rota auxiliar. O mapa de sub-páginas do NavConfig
    // NÃO conta — ele diz a que seção uma tela pertence, não leva até ela.
    final fonteRotas = File('lib/routes/app_routes.dart').readAsStringSync();
    final valores = {
      for (final m in RegExp(r"static const String (\w+)\s*=\s*'([^']+)'")
          .allMatches(fonteRotas))
        m[1]!: m[2]!,
    };

    final alcancadas = <String>{
      for (final papel in TipoUsuario.values)
        for (final item in NavConfig.itens(papel)) item.route,
      // Porta de entrada do app: ninguém navega até ela, ela abre sozinha.
      AppRoutes.splash,
    };
    final uso = RegExp(r'AppRoutes\.(\w+)');
    for (final e in fontes.entries) {
      final ehEntrada = e.key.contains('lib/views/') ||
          e.key.contains('lib/widgets/') ||
          e.key.endsWith('lib/routes/abrir_avaliacao.dart') ||
          e.key.endsWith('lib/services/auth_service.dart');
      if (!ehEntrada) continue;
      for (final m in uso.allMatches(_semComentarios(e.value))) {
        final caminho = valores[m[1]!];
        if (caminho != null) alcancadas.add(caminho);
      }
    }

    final orfas = rotasDoApp().keys.toSet().difference(alcancadas);
    expect(orfas, isEmpty,
        reason: 'tela registrada que nenhum botão abre é tela morta');
  });
}
