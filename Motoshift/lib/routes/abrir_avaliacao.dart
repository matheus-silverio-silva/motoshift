import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart' show rotasDoApp;
import '../models/turno.dart';
import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/breakpoints.dart';
import '../views/avaliacao/avaliacao_screen.dart';
import '../views/avaliar_entregadores/avaliar_entregadores_screen.dart';
import 'app_routes.dart';

/// Abre a avaliação de um turno, do jeito certo para o papel de quem pediu.
///
/// <h3>Por que é uma função, e não cada tela decidindo</h3>
/// "Avaliar" é alcançável de cinco lugares — detalhe do turno, notificação,
/// painel de pendências, central de Avaliações e Histórico —, e a escolha do
/// destino tem duas regras que precisam valer nos cinco:
///
/// * **o lojista avalia por entregador**, porque um turno multi-vaga tem uma
///   avaliação por pessoa; o entregador avalia uma loja só;
/// * **o nome mostrado é o de quem está sendo avaliado**, não o título do
///   turno — ver [nomeDoLojista].
///
/// Enquanto cada tela montava os argumentos por conta própria, as duas regras
/// valiam em umas e não em outras: três telas passavam `nomeAvaliado:
/// turno.titulo`, e a tela de avaliação mostrava "Turno Noite — Hamburgueria"
/// no lugar do nome do lojista.
Future<void> abrirAvaliacao(BuildContext context, Turno turno) async {
  final auth = context.read<AuthService>();
  final avaliadorId = auth.usuario?.id;
  if (avaliadorId == null || turno.id == null) return;

  if (auth.usuario?.tipo == TipoUsuario.lojista) {
    await Navigator.pushNamed(
      context,
      AppRoutes.avaliarEntregadores,
      arguments: AvaliarEntregadoresArgs(
        turnoId: turno.id!,
        tituloTurno: turno.titulo,
      ),
    );
    return;
  }

  // O entregador avalia a loja: o nome vem do perfil público do lojista, que
  // é o único lugar onde ele existe — TurnoResponse carrega só o lojistId.
  final nome = await nomeDoLojista(context, turno);
  if (!context.mounted) return;

  await _abrirAvaliacaoDaLoja(
    context,
    AvaliacaoArgs(
      turnoId: turno.id!,
      avaliadorId: avaliadorId,
      avaliadoId: turno.lojistId,
      nomeAvaliado: nome,
    ),
  );
}

/// Abre `/avaliacao` — página no celular, **modal de verdade** no desktop.
///
/// [AvaliacaoScreen] já desenhava o modal de 480px do artboard 12, com o
/// fundo escurecido e tudo; o que faltava era a rota. Sendo opaca, ela pintava
/// por cima da tela inteira: o escurecido não escurecia nada, porque atrás
/// dele não havia nada — o master-detail que a pessoa estava usando havia sido
/// substituído. Com `opaque: false` a tela de origem continua na árvore e
/// aparece através do próprio scrim que a avaliação pinta.
///
/// `rotasDoApp()` continua sendo quem constrói a tela, e `settings` leva nome
/// e argumentos: do lado de dentro nada muda, e `ModalRoute.of(context)`
/// devolve os mesmos argumentos de sempre.
///
/// A mesma ideia não vale para `/avaliar-entregadores`: aquela tela é um
/// `AdaptiveScaffold` com corpo de desktop próprio — uma página, não um
/// diálogo.
Future<void> _abrirAvaliacaoDaLoja(
    BuildContext context, AvaliacaoArgs args) async {
  if (!context.isDesktop) {
    await Navigator.pushNamed(context, AppRoutes.avaliacao, arguments: args);
    return;
  }

  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      // Sem barreira própria: o scrim é o `backgroundColor` translúcido do
      // Scaffold da avaliação. Duas camadas escureceriam o dobro.
      barrierColor: null,
      settings: RouteSettings(name: AppRoutes.avaliacao, arguments: args),
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, __) => rotasDoApp()[AppRoutes.avaliacao]!(ctx),
      transitionsBuilder: (_, animacao, __, filho) =>
          FadeTransition(opacity: animacao, child: filho),
    ),
  );
}

/// O nome da loja de um turno.
///
/// `TurnoResponse` não traz o nome do lojista — só `lojistId` —, então o dado
/// vem do perfil público (`GET /api/usuarios/{id}`), que devolve nome e nome
/// fantasia. Se a busca falhar, cai no título do turno: é o que havia antes, e
/// serve como último recurso, mas não como regra.
Future<String> nomeDoLojista(BuildContext context, Turno turno) async {
  try {
    final perfil = await context
        .read<ApiService>()
        .usuarios
        .buscarPerfilPublico(turno.lojistId);
    return perfil.nomeDeExibicao;
  } catch (_) {
    return turno.titulo;
  }
}
