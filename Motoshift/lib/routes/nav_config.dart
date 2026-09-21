import 'package:flutter/material.dart';

import '../models/usuario.dart';
import 'app_routes.dart';

/// O mapa de navegação do aplicativo — **a única fonte de verdade**.
///
/// <h3>Por que existe</h3>
/// A navegação estava escrita em quatro lugares que precisavam concordar e não
/// concordavam: a barra lateral do desktop tinha a lista completa, a gaveta do
/// celular a reaproveitava, e **sete telas** carregavam um `switch (i)` copiado
/// à mão para a barra inferior. O resultado previsível: a Agenda montava a
/// barra do lojista para os dois papéis, então o entregador tocava em "Início"
/// e caía no dashboard do lojista, que o AuthGuard devolvia para o dashboard
/// dele — um item de menu que não levava a lugar nenhum.
///
/// Aqui o menu é declarado uma vez por papel. [AppSidebar], [AppNavDrawer] e
/// [AppBottomNav] leem daqui, e nenhuma tela escolhe rota, papel ou índice: ela
/// informa só em que seção está.
///
/// <h3>A regra de navegação</h3>
/// Duas categorias, e só duas:
///
/// * **Item de menu ou da barra inferior = troca de seção.** Substitui a pilha
///   inteira ([irParaSecao]). Seções são irmãs, não empilhadas: ir de "Turnos"
///   para "Carteira" e depois para "Perfil" não pode deixar três telas
///   empilhadas atrás, porque o botão voltar passaria a contar a história de
///   uma navegação que o usuário não fez.
/// * **Detalhe, formulário ou sub-página = empilha.** `pushNamed` comum, volta
///   com `pop`. Aqui a pilha é a história certa: o detalhe do turno veio de
///   alguma lista, e voltar devolve para ela.
///
/// Como a troca de seção esvazia a pilha, **toda tela de seção precisa de outra
/// saída** — e é por isso que o menu (gaveta) aparece no lugar da seta quando
/// não há para onde voltar. Ver [AdaptiveScaffold] e [AppHeader].
class NavConfig {
  NavConfig._();

  // ── Menu por papel ────────────────────────────────────────────────────────

  static List<NavSection> secoes(TipoUsuario papel) =>
      papel == TipoUsuario.lojista ? _lojista : _motoboy;

  /// Os quatro itens da barra inferior, na ordem em que aparecem.
  ///
  /// Quatro é o limite do desenho, não uma escolha arbitrária: com cinco, o
  /// rótulo de 8px não cabe em 390px de largura. São os destinos do dia a dia;
  /// o resto vive no menu, que é completo.
  static List<NavItem> barraInferior(TipoUsuario papel) =>
      [for (final s in secoes(papel)) ...s.items.where((i) => i.naBarraInferior)];

  /// Todos os itens do papel, achatados.
  static List<NavItem> itens(TipoUsuario papel) =>
      [for (final s in secoes(papel)) ...s.items];

  /// A raiz do papel — para onde ir quando não há mais pilha.
  static String raizDe(TipoUsuario papel) => papel == TipoUsuario.lojista
      ? AppRoutes.dashboardLojista
      : AppRoutes.dashboardMotoboy;

  // ── Destaque do menu ──────────────────────────────────────────────────────

  /// A seção a que uma rota pertence.
  ///
  /// Sub-página destaca a seção que a contém: quem está no Extrato continua
  /// vendo "Carteira" marcada, porque foi por ali que chegou. Antes cada tela
  /// declarava isso à mão em `desktopSelectedRoute`, e duas erraram — o Saldo
  /// do lojista marcava "Carteira" (item que nem existe no menu dele) e o
  /// Histórico marcava "Perfil".
  ///
  /// Devolve `null` para rota que não pertence a seção nenhuma (login, splash,
  /// detalhe de turno): nada fica destacado, que é o correto.
  static String? secaoDe(String? rota) {
    if (rota == null) return null;
    return _subPaginas[rota] ?? (_ehSecao(rota) ? rota : null);
  }

  static bool _ehSecao(String rota) =>
      _lojista.any((s) => s.items.any((i) => i.route == rota)) ||
      _motoboy.any((s) => s.items.any((i) => i.route == rota));

  /// Sub-página → seção que a contém.
  static const Map<String, String> _subPaginas = {
    AppRoutes.extrato: AppRoutes.carteira,
    AppRoutes.lancamento: AppRoutes.carteira,
    AppRoutes.recarga: AppRoutes.carteira,
    AppRoutes.dadosPessoais: AppRoutes.perfil,
    AppRoutes.cnhVeiculo: AppRoutes.perfil,
  };

  // ── Navegação ─────────────────────────────────────────────────────────────

  /// Troca de seção: substitui a pilha inteira.
  ///
  /// `(_) => false` e não `ModalRoute.withName(raiz)`: a raiz do papel é ela
  /// própria uma seção, e manter o dashboard embaixo de toda tela faria o botão
  /// voltar reaparecer em lugares onde a pilha deveria estar vazia.
  /// @param argumentos estado inicial da seção — a aba a abrir, o diálogo a
  ///        mostrar. Com argumentos a navegação acontece mesmo estando já na
  ///        rota: "abrir a Carteira no saque" é um pedido diferente de "ir
  ///        para a Carteira".
  static void irParaSecao(BuildContext context, String rota,
      {Object? argumentos}) {
    final atual = ModalRoute.of(context)?.settings.name;
    if (atual == rota && argumentos == null) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(rota, (_) => false, arguments: argumentos);
  }

  /// A saída de uma tela sem pilha: a raiz do papel de quem está logado.
  ///
  /// Chamada pelo [AppHeader] quando a seta de voltar não teria para onde ir.
  /// Antes esse caso dava `pop` na última rota e deixava a tela em branco.
  static void voltarParaRaiz(BuildContext context, TipoUsuario? papel) {
    irParaSecao(context, raizDe(papel ?? TipoUsuario.motoboy));
  }

  // ── Definição dos menus ───────────────────────────────────────────────────
  //
  // Os rótulos aqui são os MESMOS que aparecem no título da tela e no botão que
  // leva até ela — ver docs/ux/NAVEGACAO.md. Um conceito, um nome.

  static final List<NavSection> _lojista = [
    NavSection(label: 'OPERAÇÃO', items: [
      const NavItem(
        icon: Icons.home_outlined,
        label: 'Início',
        route: AppRoutes.dashboardLojista,
        naBarraInferior: true,
      ),
      const NavItem(
        icon: Icons.calendar_month_outlined,
        label: 'Agenda',
        route: AppRoutes.agenda,
        naBarraInferior: true,
      ),
      const NavItem(
        icon: Icons.local_shipping_outlined,
        label: 'Turnos',
        route: AppRoutes.turnosLojista,
        naBarraInferior: true,
      ),
      const NavItem(
        icon: Icons.add_box_outlined,
        label: 'Publicar turno',
        route: AppRoutes.publicarTurno,
      ),
    ]),
    NavSection(label: 'FINANCEIRO', items: [
      const NavItem(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Saldo',
        route: AppRoutes.saldoLojista,
      ),
      const NavItem(
        icon: Icons.insights_outlined,
        label: 'Relatórios',
        route: AppRoutes.relatorioFinanceiro,
      ),
      const NavItem(
        icon: Icons.receipt_long_outlined,
        label: 'Notas fiscais',
        route: AppRoutes.notasFiscais,
      ),
    ]),
    NavSection(label: 'AVALIAÇÕES', items: [
      const NavItem(
        icon: Icons.star_outline_rounded,
        label: 'Avaliações',
        route: AppRoutes.minhasAvaliacoes,
        badge: NavBadge.avaliacoes,
      ),
    ]),
    NavSection(label: 'CONTA', items: [
      const NavItem(
        icon: Icons.notifications_outlined,
        label: 'Notificações',
        route: AppRoutes.notificacoes,
        badge: NavBadge.notificacoes,
      ),
      const NavItem(
        icon: Icons.history_rounded,
        label: 'Histórico',
        route: AppRoutes.historicoTurnos,
      ),
      const NavItem(
        icon: Icons.person_outline_rounded,
        label: 'Perfil',
        route: AppRoutes.perfil,
        naBarraInferior: true,
      ),
    ]),
  ];

  static final List<NavSection> _motoboy = [
    NavSection(label: 'OPERAÇÃO', items: [
      const NavItem(
        icon: Icons.home_outlined,
        label: 'Início',
        route: AppRoutes.dashboardMotoboy,
        naBarraInferior: true,
      ),
      const NavItem(
        icon: Icons.two_wheeler_outlined,
        label: 'Turnos',
        route: AppRoutes.turnosDisponiveis,
        naBarraInferior: true,
      ),
      const NavItem(
        icon: Icons.calendar_month_outlined,
        label: 'Agenda',
        route: AppRoutes.agenda,
      ),
    ]),
    NavSection(label: 'FINANCEIRO', items: [
      const NavItem(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Carteira',
        route: AppRoutes.carteira,
        naBarraInferior: true,
      ),
      const NavItem(
        icon: Icons.insights_outlined,
        label: 'Relatórios',
        route: AppRoutes.relatorioFinanceiro,
      ),
      const NavItem(
        icon: Icons.receipt_long_outlined,
        label: 'Notas fiscais',
        route: AppRoutes.notasFiscais,
      ),
    ]),
    NavSection(label: 'AVALIAÇÕES', items: [
      const NavItem(
        icon: Icons.star_outline_rounded,
        label: 'Avaliações',
        route: AppRoutes.minhasAvaliacoes,
        badge: NavBadge.avaliacoes,
      ),
    ]),
    NavSection(label: 'CONTA', items: [
      const NavItem(
        icon: Icons.notifications_outlined,
        label: 'Notificações',
        route: AppRoutes.notificacoes,
        badge: NavBadge.notificacoes,
      ),
      const NavItem(
        icon: Icons.history_rounded,
        label: 'Histórico',
        route: AppRoutes.historicoTurnos,
      ),
      const NavItem(
        icon: Icons.person_outline_rounded,
        label: 'Perfil',
        route: AppRoutes.perfil,
        naBarraInferior: true,
      ),
    ]),
  ];
}

/// Que contador aparece ao lado do item, quando houver.
enum NavBadge { nenhum, notificacoes, avaliacoes }

/// Um destino do menu.
class NavItem {
  const NavItem({
    required this.icon,
    required this.label,
    required this.route,
    this.badge = NavBadge.nenhum,
    this.naBarraInferior = false,
  });

  final IconData icon;

  /// O nome do conceito — o mesmo no menu, na barra inferior e no título da
  /// tela. Ver a tabela em docs/ux/NAVEGACAO.md.
  final String label;

  final String route;
  final NavBadge badge;

  /// Se este item também é um dos quatro atalhos da barra inferior.
  final bool naBarraInferior;
}

/// Um grupo de itens sob um rótulo ("OPERAÇÃO", "FINANCEIRO"…).
class NavSection {
  const NavSection({required this.label, required this.items});

  final String label;
  final List<NavItem> items;
}
