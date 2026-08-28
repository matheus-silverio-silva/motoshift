import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Layout master-detail do desktop: lista fixa de 380px à esquerda e painel de
/// detalhe à direita, os dois na mesma tela (artboards 5 e 8 do protótipo v2).
class MasterDetailLayout extends StatelessWidget {
  const MasterDetailLayout({
    required this.list,
    required this.detail,
    this.listHeader,
    super.key,
  });

  static const double listWidth = 380;

  /// Conteúdo rolável da coluna esquerda.
  final Widget list;

  /// Painel direito — o detalhe do item selecionado, ou [MasterDetailEmpty].
  final Widget detail;

  /// Faixa fixa no topo da lista (contagem, filtros ativos).
  final Widget? listHeader;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: listWidth,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              right: BorderSide(color: AppColors.line, width: 1.5),
            ),
          ),
          child: Column(
            children: [
              if (listHeader != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.line, width: 1.5),
                    ),
                  ),
                  child: listHeader,
                ),
              Expanded(child: list),
            ],
          ),
        ),
        Expanded(child: detail),
      ],
    );
  }
}

/// Faixa de cabeçalho da lista — contagem à esquerda, informação auxiliar à
/// direita ou uma ação.
class MasterDetailListHeader extends StatelessWidget {
  const MasterDetailListHeader({
    required this.titulo,
    this.info,
    this.trailing,
    super.key,
  });

  final String titulo;
  final String? info;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tsJakarta(12.5, FontWeight.w700, color: AppColors.text),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (info != null)
          Text(
            info!,
            style: tsJakarta(11.5, FontWeight.w400, color: AppColors.muted),
          ),
      ],
    );
  }
}

/// Estado do painel direito quando nada está selecionado.
class MasterDetailEmpty extends StatelessWidget {
  const MasterDetailEmpty({
    required this.icon,
    required this.titulo,
    this.subtitulo,
    super.key,
  });

  final IconData icon;
  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: AppColors.tealDeep),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: tsBricolage(17, FontWeight.w800, color: AppColors.ink),
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitulo!,
                textAlign: TextAlign.center,
                style: tsJakarta(13, FontWeight.w400, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
