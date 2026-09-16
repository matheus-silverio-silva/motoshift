import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';

/// Ponto plotado no mapa além do centro — um turno, uma loja, um entregador.
@immutable
class MapaPonto {
  const MapaPonto({
    required this.posicao,
    this.rotulo,
    this.icone = Icons.storefront_rounded,
    this.cor = AppColors.amber,
    this.onTap,
  });

  final LatLng posicao;

  /// Texto curto sob o pino (ex.: "R$ 90"). Nulo = só o pino.
  final String? rotulo;
  final IconData icone;
  final Color cor;
  final VoidCallback? onTap;
}

/// Mapa do app: um centro, um círculo de raio opcional e os pontos ao redor.
///
/// Três coisas que a versão anterior não fazia e que são a razão de este widget
/// ter estado:
///
/// 1. **Enquadra o que desenha.** O zoom vinha de uma escada de `if`s sobre o
///    raio, ignorando a altura do widget — o círculo de 30 km vazava para fora
///    da moldura e o de 1 km virava um ponto perdido. Agora a câmera parte de
///    um [CameraFit] calculado sobre o retângulo que contém o círculo e todos
///    os pontos.
/// 2. **Reenquadra quando o raio muda.** `initialCameraFit` só vale na primeira
///    montagem; arrastar o slider mudava o círculo e deixava o zoom para trás.
///    O [didUpdateWidget] refaz o fit.
/// 3. **Assume quando o tile não vem.** O servidor de tiles é público e falha
///    (limite de requisições, rede caída, app offline). Sem tratamento o mapa
///    só ficava cinza. Aqui a falha vira uma tarja explicando o motivo, com
///    "Tentar novamente" — e há um espelho como [TileLayer.fallbackUrl] antes
///    de chegar nisso.
class MapaRaio extends StatefulWidget {
  const MapaRaio({
    required this.centro,
    this.raioKm,
    this.pontos = const [],
    this.height = 180,
    this.iconeCentro = Icons.storefront_rounded,
    this.interativo = false,
    this.onTapMapa,
    this.rodape,
    super.key,
  });

  final LatLng centro;

  /// Raio do círculo em km. Nulo desenha só o pino do centro.
  final double? raioKm;

  final List<MapaPonto> pontos;
  final double height;
  final IconData iconeCentro;

  /// Libera arrastar e dar zoom. Padrão falso: na maioria das telas o mapa é
  /// ilustração, e um mapa que rola dentro de uma lista rouba o gesto dela.
  final bool interativo;

  /// Chamado quando o usuário toca o mapa — usado por "escolher o ponto de
  /// partida" na publicação do turno. Informar também liga a interação.
  final ValueChanged<LatLng>? onTapMapa;

  /// Etiqueta no canto inferior esquerdo (região, endereço).
  final String? rodape;

  @override
  State<MapaRaio> createState() => _MapaRaioState();
}

class _MapaRaioState extends State<MapaRaio> {
  final MapController _controller = MapController();

  /// Quantos tiles falharam desde a última tentativa. Um ou outro é normal
  /// (borda do mundo, tile ausente no servidor); vários seguidos significam
  /// que o mapa não vai aparecer, e aí vale avisar em vez de mostrar cinza.
  int _tilesComErro = 0;

  /// Trocar a chave desmonta o [TileLayer] e força o recarregamento — é o que
  /// o botão "Tentar novamente" faz.
  int _tentativa = 0;

  bool _mapaPronto = false;

  static const int _limiteDeErros = 4;

  /// Quantos km cabem em um grau de latitude — constante em qualquer latitude.
  /// É o mesmo número que o `GeoUtils` do backend usa na bounding box.
  static const double _kmPorGrauLat = 111.32;

  bool get _semTiles => _tilesComErro >= _limiteDeErros;

  @override
  void didUpdateWidget(covariant MapaRaio old) {
    super.didUpdateWidget(old);
    final mudouCentro = old.centro != widget.centro;
    final mudouRaio = old.raioKm != widget.raioKm;
    final mudaramPontos = old.pontos.length != widget.pontos.length;
    if (_mapaPronto && (mudouCentro || mudouRaio || mudaramPontos)) {
      // Fora do frame de build: mexer na câmera durante o layout dispara
      // asserção no flutter_map.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.fitCamera(_enquadramento());
      });
    }
  }

  /// Retângulo que contém o círculo do raio e todos os pontos plotados.
  CameraFit _enquadramento() {
    return CameraFit.bounds(
      bounds: _limites(),
      padding: const EdgeInsets.all(24),
      // Sem teto o fit de um ponto único vai para o zoom máximo e o mapa vira
      // uma calçada sem contexto.
      maxZoom: 16,
    );
  }

  LatLngBounds _limites() {
    final raio = widget.raioKm;
    final pontos = <LatLng>[widget.centro, ...widget.pontos.map((p) => p.posicao)];

    if (raio != null && raio > 0) {
      // Meia-altura e meia-largura em graus do quadrado que circunscreve o
      // círculo. A longitude encolhe com o cosseno da latitude.
      final dLat = raio / _kmPorGrauLat;
      // Perto dos polos um grau de longitude vale quase nada; o piso evita a
      // divisão por ~zero (e, com ela, um bounds infinito).
      final cos =
          math.max(math.cos(widget.centro.latitude * math.pi / 180).abs(), 0.01);
      final dLng = raio / (_kmPorGrauLat * cos);
      pontos
        ..add(LatLng(widget.centro.latitude - dLat, widget.centro.longitude - dLng))
        ..add(LatLng(widget.centro.latitude + dLat, widget.centro.longitude + dLng));
    }

    var sul = pontos.first.latitude;
    var norte = pontos.first.latitude;
    var oeste = pontos.first.longitude;
    var leste = pontos.first.longitude;
    for (final p in pontos) {
      if (p.latitude < sul) sul = p.latitude;
      if (p.latitude > norte) norte = p.latitude;
      if (p.longitude < oeste) oeste = p.longitude;
      if (p.longitude > leste) leste = p.longitude;
    }

    // Um retângulo de área zero (um ponto só, sem raio) não tem enquadramento
    // possível; abre-se uma margem mínima de ~300 m.
    const minimo = 0.003;
    if (norte - sul < minimo) {
      norte += minimo / 2;
      sul -= minimo / 2;
    }
    if (leste - oeste < minimo) {
      leste += minimo / 2;
      oeste -= minimo / 2;
    }

    return LatLngBounds(LatLng(sul, oeste), LatLng(norte, leste));
  }

  void _recarregarTiles() {
    setState(() {
      _tilesComErro = 0;
      _tentativa++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final interativo = widget.interativo || widget.onTapMapa != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(child: _buildMapa(interativo)),
            if (_semTiles) Positioned.fill(child: _buildTilesIndisponiveis()),
            if (widget.rodape != null && !_semTiles)
              Positioned(bottom: 10, left: 10, child: _buildRodape()),
            if (!_semTiles)
              const Positioned(bottom: 3, right: 6, child: _Atribuicao()),
          ],
        ),
      ),
    );
  }

  Widget _buildMapa(bool interativo) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCameraFit: _enquadramento(),
        backgroundColor: AppColors.surface2,
        onMapReady: () => _mapaPronto = true,
        onTap: widget.onTapMapa == null
            ? null
            : (_, ponto) => widget.onTapMapa!(ponto),
        interactionOptions: InteractionOptions(
          flags: interativo
              ? InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          key: ValueKey('tiles-$_tentativa'),
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // Espelho oficial do projeto OSM. Quando o primeiro recusa (limite
          // de requisições é o caso comum), o tile ainda chega por aqui em vez
          // de deixar o quadrado cinza.
          fallbackUrl:
              'https://tile-a.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.motoshift.app',
          maxNativeZoom: 19,
          errorTileCallback: (_, __, ___) {
            // Fora do frame: o callback roda durante o paint do tile.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _tilesComErro < _limiteDeErros) {
                setState(() => _tilesComErro++);
              }
            });
          },
        ),
        if (widget.raioKm != null && widget.raioKm! > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: widget.centro,
                radius: widget.raioKm! * 1000,
                useRadiusInMeter: true,
                color: AppColors.teal.withOpacity(0.15),
                borderColor: AppColors.teal,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        if (widget.pontos.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final p in widget.pontos)
                Marker(
                  point: p.posicao,
                  width: 74,
                  height: p.rotulo == null ? 34 : 48,
                  alignment: Alignment.topCenter,
                  child: _PinoPonto(ponto: p),
                ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.centro,
              width: 34,
              height: 34,
              child: _PinoCentro(icone: widget.iconeCentro),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTilesIndisponiveis() {
    return ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 28, color: AppColors.muted),
              const SizedBox(height: 6),
              Text(
                'Não foi possível carregar o mapa',
                textAlign: TextAlign.center,
                style: tsJakarta(11.5, FontWeight.w700, color: AppColors.text),
              ),
              const SizedBox(height: 2),
              Text(
                widget.rodape ?? 'Verifique sua conexão.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _recarregarTiles,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: Text('Tentar novamente',
                    style: tsJakarta(11.5, FontWeight.w700,
                        color: AppColors.tealDeep)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDeep,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRodape() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.ink.withOpacity(0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              widget.rodape!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tsJakarta(10, FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Crédito exigido pela licença dos tiles do OpenStreetMap.
class _Atribuicao extends StatelessWidget {
  const _Atribuicao();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('© OpenStreetMap',
          style: tsJakarta(7.5, FontWeight.w500, color: AppColors.muted)),
    );
  }
}

class _PinoCentro extends StatelessWidget {
  const _PinoCentro({required this.icone});
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.teal,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Icon(icone, color: Colors.white, size: 16),
    );
  }
}

class _PinoPonto extends StatelessWidget {
  const _PinoPonto({required this.ponto});
  final MapaPonto ponto;

  @override
  Widget build(BuildContext context) {
    final pino = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: ponto.cor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(ponto.icone, size: 14, color: AppColors.onTertiary),
        ),
        if (ponto.rotulo != null) ...[
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.ink.withOpacity(0.82),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ponto.rotulo!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tsJakarta(9, FontWeight.w800, color: Colors.white),
            ),
          ),
        ],
      ],
    );

    if (ponto.onTap == null) return pino;
    return GestureDetector(
      onTap: ponto.onTap,
      behavior: HitTestBehavior.opaque,
      child: pino,
    );
  }
}
