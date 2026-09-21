// Regras de estrutura que uma tela nova pode quebrar sem perceber.
//
// A navegação chegou a estar escrita em sete telas, cada uma com um
// `switch (i)` copiado para a barra inferior — e a Agenda, compartilhada
// pelos dois papéis, montava a barra do lojista para o entregador. O
// NavConfig acabou com isso, mas nada impede a próxima tela de trazer o
// padrão de volta. Estes testes leem o código-fonte e a tabela de rotas e
// falham se:
//
//   * alguma tela montar a própria barra inferior ou o próprio switch de
//     navegação;
//   * uma tela declarar como seção uma rota que não é item de menu;
//   * uma tela declarar uma seção que falta no menu de um papel que pode
//     abri-la — o erro exato da Agenda.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moto_shift/app.dart';
import 'package:moto_shift/models/usuario.dart';
import 'package:moto_shift/routes/nav_config.dart';
import 'package:moto_shift/widgets/auth_guard.dart';

/// Os arquivos das telas, com o conteúdo lido uma vez.
Map<String, String> _fontesDasTelas() => {
      for (final f in Directory('lib/views')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
    };

/// `AppRoutes.nome` → `/caminho`, lido do próprio app_routes.dart.
Map<String, String> _valoresDasRotas() {
  final fonte = File('lib/routes/app_routes.dart').readAsStringSync();
  final re = RegExp(r"static const String (\w+)\s*=\s*'([^']+)'");
  return {for (final m in re.allMatches(fonte)) m.group(1)!: m.group(2)!};
}

void main() {
  final fontes = _fontesDasTelas();
  final rotas = _valoresDasRotas();

  test('nenhuma tela monta a própria barra inferior ou o próprio switch', () {
    // A barra é do AdaptiveScaffold; a tela informa só a seção.
    final proibidos = <RegExp, String>{
      RegExp(r'AppBottomNav\('): 'monta AppBottomNav',
      RegExp(r'BottomNavigationBar\('): 'monta BottomNavigationBar',
      RegExp(r'\bNavigationBar\('): 'monta NavigationBar',
      RegExp(r'bottomNav\s*:'): 'passa bottomNav ao scaffold',
      RegExp(r'void _onNav\('): 'tem um _onNav próprio',
    };
    final violacoes = [
      for (final e in fontes.entries)
        for (final p in proibidos.entries)
          if (p.key.hasMatch(e.value)) '${e.key}: ${p.value}',
    ];
    expect(violacoes, isEmpty,
        reason: 'a navegação vem do NavConfig — ver lib/routes/nav_config.dart');
  });

  test('toda seção declarada por uma tela é item de menu', () {
    final re = RegExp(r'rotaDaSecao:\s*AppRoutes\.(\w+)');
    final declaradas = <String, String>{};
    for (final e in fontes.entries) {
      for (final m in re.allMatches(e.value)) {
        declaradas[e.key] = rotas[m.group(1)!]!;
      }
    }
    expect(declaradas, isNotEmpty);
    for (final e in declaradas.entries) {
      expect(NavConfig.secaoDe(e.value), e.value,
          reason: '${e.key} declara rotaDaSecao ${e.value}, que não é item '
              'de menu de nenhum papel');
    }
  });

  testWidgets('a seção de cada tela está no menu de todo papel que a abre',
      (tester) async {
    // A tabela de rotas diz quem pode abrir cada tela (o papel do AuthGuard,
    // ou os dois quando ele é nulo); o código da tela diz a seção. Os dois
    // precisam concordar.
    late BuildContext contexto;
    await tester.pumpWidget(Builder(builder: (c) {
      contexto = c;
      return const SizedBox();
    }));

    final reSecao = RegExp(r'rotaDaSecao:\s*AppRoutes\.(\w+)');
    final problemas = <String>[];
    var verificadas = 0;

    for (final entrada in rotasDoApp().entries) {
      final Widget construido;
      try {
        construido = entrada.value(contexto);
      } catch (_) {
        continue; // rota que depende de argumento — não é seção
      }
      if (construido is! AuthGuard) continue;

      final tipo = construido.child.runtimeType.toString();
      final arquivo = fontes.entries
          .where((e) => e.value.contains('class $tipo '))
          .map((e) => e.key)
          .firstOrNull;
      if (arquivo == null) continue;

      final m = reSecao.firstMatch(fontes[arquivo]!);
      if (m == null) continue; // sub-página: não declara seção
      final secao = rotas[m.group(1)!]!;
      verificadas++;

      final papeis = construido.papel == null
          ? TipoUsuario.values
          : [construido.papel!];
      for (final papel in papeis) {
        final noMenu = NavConfig.itens(papel).any((i) => i.route == secao);
        if (!noMenu) {
          problemas.add('${entrada.key} ($tipo) pode ser aberta pelo '
              '${papel.name}, mas declara a seção $secao, que não está no '
              'menu dele');
        }
      }
    }

    // Sem isto o teste passaria em silêncio se a busca dos arquivos
    // quebrasse — nenhuma tela verificada, nenhum problema encontrado.
    expect(verificadas, greaterThanOrEqualTo(12),
        reason: 'o teste deixou de encontrar as telas de seção');
    expect(problemas, isEmpty);
  });
}
