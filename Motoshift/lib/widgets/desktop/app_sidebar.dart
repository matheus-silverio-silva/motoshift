import 'package:flutter/material.dart';
import '../../routes/nav_config.dart';
import '../../theme/app_theme.dart';

// As classes SidebarItem, SidebarSection e SidebarItems viviam aqui e
// definiam o menu do desktop. Elas saíram para o NavConfig: o mesmo menu
// precisava valer para a barra lateral, para a gaveta do celular e para a
// barra inferior, e enquanto a definição morava no widget do desktop, os
// outros dois a copiavam — foi assim que a barra inferior acabou com um
// switch próprio em sete telas.
//
// Este arquivo voltou a ser só o desenho da barra: recebe as seções prontas e
// as pinta.

/// Barra lateral de 240px com gradiente teal → tealDeep (135°).
/// Logo, grupos de navegação e, no rodapé, o bloco do usuário e "Sair".
///
/// O miolo rola: com o menu completo os itens passam de dez, e em janela
/// baixa (ou no menu lateral do celular) a lista precisa caber sem estourar.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.sections,
    required this.userName,
    required this.userSubtitle,
    required this.userInitials,
    this.selectedRoute,
    this.badges = const {},
    this.onSelect,
    this.onLogout,
    super.key,
  });

  static const double width = 240;

  final List<NavSection> sections;
  final String userName;
  final String userSubtitle;
  final String userInitials;

  /// Rota destacada — a SEÇÃO, não necessariamente a rota atual: quem está no
  /// Extrato vê "Carteira" marcada. Ver [NavConfig.secaoDe].
  final String? selectedRoute;

  /// Contadores por tipo de badge, já resolvidos por quem tem os providers.
  /// O widget não busca nada: ele desenha o que recebe.
  final Map<NavBadge, String?> badges;

  /// Substitui a navegação padrão ([NavConfig.irParaSecao]) quando informado —
  /// a gaveta usa isto para se fechar antes de navegar.
  final ValueChanged<NavItem>? onSelect;
  final VoidCallback? onLogout;

  // Tons translucidos sobre o gradiente, conforme o canvas.
  static const Color _navLabel = Color(0xB3BFE5E3); // rgba(191,229,227,.7)
  static const Color _itemFg = Color(0xD1EAFFFD); // rgba(234,255,253,.82)
  static const Color _itemBgActive = Color(0x2EFFFFFF); // rgba(255,255,255,.18)
  static const Color _footerLine = Color(0x24FFFFFF); // rgba(255,255,255,.14)
  static const Color _avatarBg = Color(0x29FFFFFF); // rgba(255,255,255,.16)
  static const Color _avatarBorder = Color(0x38FFFFFF); // rgba(255,255,255,.22)
  static const Color _userSubtitleFg = Color(0xD9BFE5E3); // rgba(191,229,227,.85)
  static const Color _logoutFg = Color(0xB8EAFFFD); // rgba(234,255,253,.72)

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLogo(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              children: [
                for (final section in sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Text(
                      section.label,
                      style: tsJakarta(9.5, FontWeight.w700, color: _navLabel)
                          .copyWith(letterSpacing: 9.5 * .12),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        for (final item in section.items) ...[
                          _SidebarTile(
                            item: item,
                            badge: badges[item.badge],
                            selected: item.route == selectedRoute,
                            onTap: () => _handleTap(context, item),
                          ),
                          if (item != section.items.last)
                            const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, NavItem item) {
    if (onSelect != null) {
      onSelect!(item);
      return;
    }
    // Item de menu e troca de secao: substitui a pilha inteira. Antes era
    // pushReplacementNamed, que troca so o topo — e deixava a tela nova sem
    // pilha E sem gaveta, com uma seta de voltar que dava pop na ultima rota.
    NavConfig.irParaSecao(context, item.route);
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.two_wheeler_outlined,
                size: 22, color: Color(0xFFFFFFFF)),
          ),
          const SizedBox(width: 10),
          Text.rich(
            TextSpan(
              text: 'Moto',
              style: tsBricolage(18, FontWeight.w800,
                  color: const Color(0xFFFFFFFF)),
              children: [
                TextSpan(
                  text: 'Shift',
                  style: tsBricolage(18, FontWeight.w800,
                      color: AppColors.tealBright),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _footerLine, width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _avatarBg,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _avatarBorder, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        userInitials,
                        style: tsBricolage(13, FontWeight.w800,
                            color: const Color(0xFFEAFFFD)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(12.5, FontWeight.w700,
                              color: const Color(0xFFFFFFFF)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tsJakarta(10.5, FontWeight.w400,
                              color: _userSubtitleFg),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onLogout,
            borderRadius: BorderRadius.circular(12),
            hoverColor: const Color(0x1AFFFFFF),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.logout_outlined,
                        size: 18, color: _logoutFg),
                    const SizedBox(width: 12),
                    Text('Sair',
                        style: tsJakarta(12.5, FontWeight.w600,
                            color: _logoutFg)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final NavItem item;

  /// Texto do contador, ja resolvido. Null = sem badge.
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? const Color(0xFFFFFFFF) : AppSidebar._itemFg;
    return Material(
      color: selected ? AppSidebar._itemBgActive : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0x1AFFFFFF),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tsJakarta(
                        13, selected ? FontWeight.w700 : FontWeight.w600,
                        color: fg),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: tsJakarta(10, FontWeight.w800,
                          color: AppColors.onTertiary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
