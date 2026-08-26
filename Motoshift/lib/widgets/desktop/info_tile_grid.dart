import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Um dado do turno exibido no grid de informações do desktop.
class InfoTileData {
  const InfoTileData({
    required this.icon,
    required this.label,
    required this.valor,
  });

  final IconData icon;
  final String label;
  final String valor;
}

/// Grid de 2 colunas com gap 16 dos cards de informação do painel de detalhe
/// (artboards 5 e 8). A versão mobile usa `GridView.count` com aspect ratio
/// calibrado para 358px de largura; aqui as colunas são bem mais largas, então
/// a altura vem do conteúdo em vez de uma proporção fixa.
class InfoTileGrid extends StatelessWidget {
  const InfoTileGrid({required this.itens, super.key});

  final List<InfoTileData> itens;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itens.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 16),
          // IntrinsicHeight porque `stretch` numa Row exige altura conhecida,
          // e esta coluna é de altura livre.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _InfoTile(dado: itens[i])),
                const SizedBox(width: 16),
                Expanded(
                  child: i + 1 < itens.length
                      ? _InfoTile(dado: itens[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.dado});
  final InfoTileData dado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(dado.icon, size: 18, color: AppColors.teal),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dado.label.toUpperCase(),
                  style: tsJakarta(10, FontWeight.w700, color: AppColors.muted)
                      .copyWith(letterSpacing: 10 * .08),
                ),
                Text(
                  dado.valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tsJakarta(13, FontWeight.w700, color: AppColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
