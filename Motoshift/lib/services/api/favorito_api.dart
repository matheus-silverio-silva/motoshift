import '../../models/entregador_favorito.dart';
import 'api_client.dart';

/// Os entregadores favoritos da loja (`/api/favoritos`, só lojista).
///
/// Favoritar de novo não é erro — o backend devolve o favorito que existe —,
/// e desfavoritar o que não é favorito também não. O coração pode ser tocado
/// quantas vezes for.
class FavoritoApi {
  final ApiClient _client;

  FavoritoApi(this._client);

  Future<List<EntregadorFavorito>> listar() async {
    final data = await _client.get('/favoritos');
    return (data as List)
        .map((j) => EntregadorFavorito.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<EntregadorFavorito> favoritar(int motoboyId) async {
    final data = await _client.put('/favoritos/$motoboyId', const {});
    return EntregadorFavorito.fromJson(data as Map<String, dynamic>);
  }

  Future<void> desfavoritar(int motoboyId) async {
    await _client.delete('/favoritos/$motoboyId');
  }
}
