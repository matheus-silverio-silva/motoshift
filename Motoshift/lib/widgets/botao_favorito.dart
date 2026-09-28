import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/usuario.dart';
import '../presentation/providers/favoritos_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// O coração do lojista para um entregador (V18).
///
/// Some para quem não é lojista — o entregador não tem favoritos — e onde o
/// [FavoritosProvider] não foi registrado (vitrines e testes antigos que
/// montam só parte do app).
class BotaoFavorito extends StatefulWidget {
  const BotaoFavorito({
    required this.motoboyId,
    this.nome,
    this.comRotulo = false,
    super.key,
  });

  final int motoboyId;

  /// Para a mensagem ("Ricardo entrou nos seus favoritos").
  final String? nome;

  /// `true` mostra "Favoritar" / "Favorito" ao lado do coração.
  final bool comRotulo;

  @override
  State<BotaoFavorito> createState() => _BotaoFavoritoState();
}

class _BotaoFavoritoState extends State<BotaoFavorito> {
  FavoritosProvider? _provider(BuildContext context, {bool ouvir = true}) {
    try {
      return ouvir
          ? context.watch<FavoritosProvider>()
          : context.read<FavoritosProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final usuario = context.read<AuthService>().usuario;
      if (usuario?.tipo != TipoUsuario.lojista) return;
      _provider(context, ouvir: false)?.carregar(usuario!.id);
    });
  }

  Future<void> _alternar(FavoritosProvider p) async {
    final era = p.ehFavorito(widget.motoboyId);
    final erro = await p.alternar(widget.motoboyId);
    if (!mounted) return;
    final nome = widget.nome?.trim().split(' ').first;
    final quem = nome == null || nome.isEmpty ? 'O entregador' : nome;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(erro ??
          (era
              ? '$quem saiu dos seus favoritos.'
              : '$quem entrou nos seus favoritos. Você avisa quando publicar turno.')),
      backgroundColor: erro == null ? AppColors.teal : AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.usuario?.tipo != TipoUsuario.lojista) return const SizedBox.shrink();
    final p = _provider(context);
    if (p == null) return const SizedBox.shrink();

    final favorito = p.ehFavorito(widget.motoboyId);
    final ocupado = p.alterando(widget.motoboyId) || (p.carregando && !p.carregado);
    final icone = Icon(
      favorito ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: 20,
      color: favorito ? AppColors.error : AppColors.muted,
    );

    return Semantics(
      button: true,
      toggled: favorito,
      label: favorito ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
      child: InkWell(
        key: Key('favorito-${widget.motoboyId}'),
        onTap: ocupado ? null : () => _alternar(p),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: EdgeInsets.symmetric(horizontal: widget.comRotulo ? 12 : 0),
          alignment: Alignment.center,
          child: widget.comRotulo
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icone,
                    const SizedBox(width: 6),
                    Text(favorito ? 'Favorito' : 'Favoritar',
                        style: tsJakarta(12, FontWeight.w700,
                            color: favorito ? AppColors.error : AppColors.tealDeep)),
                  ],
                )
              : icone,
        ),
      ),
    );
  }
}
