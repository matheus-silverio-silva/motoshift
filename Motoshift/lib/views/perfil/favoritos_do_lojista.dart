import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/entregador_favorito.dart';
import '../../presentation/providers/favoritos_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/iniciais.dart';
import '../../widgets/botao_favorito.dart';
import '../perfil_publico/perfil_publico_screen.dart';

/// "Meus entregadores favoritos", no perfil do lojista (V18).
///
/// Mora no próprio perfil, e não numa tela nova: é uma lista curta, e uma rota
/// nova mudaria a navegação do app. Cada linha abre o perfil público do
/// entregador; o coração tira da lista ali mesmo.
class FavoritosDoLojista extends StatefulWidget {
  const FavoritosDoLojista({super.key});

  @override
  State<FavoritosDoLojista> createState() => _FavoritosDoLojistaState();
}

class _FavoritosDoLojistaState extends State<FavoritosDoLojista> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider(ouvir: false)
          ?.carregar(context.read<AuthService>().usuario?.id);
    });
  }

  FavoritosProvider? _provider({bool ouvir = true}) {
    try {
      return ouvir
          ? context.watch<FavoritosProvider>()
          : context.read<FavoritosProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider();
    if (p == null) return const SizedBox.shrink();

    return Container(
      key: const Key('favoritos-do-lojista'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded,
                  size: 15, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text('MEUS ENTREGADORES FAVORITOS',
                    style: tsJakarta(9.5, FontWeight.w700,
                            color: AppColors.muted)
                        .copyWith(letterSpacing: 0.8)),
              ),
              if (p.carregado && p.lista.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${p.lista.length}',
                      style: tsJakarta(11, FontWeight.w700,
                          color: AppColors.muted)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ..._conteudo(p),
        ],
      ),
    );
  }

  List<Widget> _conteudo(FavoritosProvider p) {
    if (!p.carregado && p.erro == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.teal),
            ),
          ),
        ),
      ];
    }
    if (p.erro != null && !p.carregado) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(p.erro!,
                    style: tsJakarta(11.5, FontWeight.w400,
                        color: AppColors.muted)),
              ),
              TextButton(
                onPressed: () => p.carregar(
                    context.read<AuthService>().usuario?.id,
                    forcar: true),
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      ];
    }
    if (p.lista.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 8, 10),
          child: Text(
            'Toque no coração no perfil de um entregador, ou ao avaliá-lo, '
            'para guardá-lo aqui. Quando você publicar um turno, ele fica '
            'sabendo.',
            key: const Key('favoritos-vazio'),
            style: tsJakarta(11.5, FontWeight.w400,
                color: AppColors.muted, height: 1.45),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < p.lista.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: AppColors.line),
        _Linha(favorito: p.lista[i]),
      ],
    ];
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.favorito});

  final EntregadorFavorito favorito;

  @override
  Widget build(BuildContext context) {
    final nota = favorito.mediaAvaliacao;
    return InkWell(
      key: Key('favorito-linha-${favorito.motoboyId}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.perfilPublico,
        arguments: PerfilPublicoArgs(
            usuarioId: favorito.motoboyId, nome: favorito.nome),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(iniciaisDe(favorito.nome),
                    style: tsBricolage(13, FontWeight.w800,
                        color: AppColors.tealDeep)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(favorito.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tsJakarta(12.5, FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                    nota == null
                        ? 'Ainda sem avaliações'
                        : '★ ${nota.toStringAsFixed(1).replaceAll('.', ',')}',
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted),
                  ),
                ],
              ),
            ),
            BotaoFavorito(
                motoboyId: favorito.motoboyId, nome: favorito.nome),
          ],
        ),
      ),
    );
  }
}
