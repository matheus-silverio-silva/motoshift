import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/turno.dart';
import '../theme/app_theme.dart';
import 'mapa_raio.dart';

/// O mapa de um turno: onde ele começa e até onde o entregador roda.
///
/// Substitui o antigo `MapaPlaceholder`, que escrevia "Mapa indisponível" em
/// toda tela de detalhe — sempre, mesmo com o backend devolvendo `latitude` e
/// `longitude` no turno desde o SCRUM-18. O app é que não lia os campos.
///
/// O texto de indisponível continua existindo, mas agora só para o caso em que
/// ele é verdade: turno legado, publicado antes de a coordenada existir.
class MapaTurno extends StatelessWidget {
  const MapaTurno({
    required this.turno,
    this.altura = 180,
    this.mostrarRaio = true,
    super.key,
  });

  final Turno turno;
  final double altura;

  /// Desenha o círculo do raio de entrega em volta do ponto de partida.
  final bool mostrarRaio;

  @override
  Widget build(BuildContext context) {
    final rodape = turno.endereco?.trim().isNotEmpty == true
        ? turno.endereco!.trim()
        : turno.regiao;

    if (!turno.temCoordenada) {
      return _SemCoordenada(regiao: rodape, altura: altura);
    }

    return MapaRaio(
      centro: LatLng(turno.latitude!, turno.longitude!),
      raioKm: mostrarRaio ? turno.raioEntregaKm : null,
      height: altura,
      rodape: rodape,
    );
  }
}

/// Turno sem coordenada. Não há mapa a mostrar — e dizer o porquê é melhor do
/// que um retângulo cinza com "indisponível", que sugere falha do app.
class _SemCoordenada extends StatelessWidget {
  const _SemCoordenada({required this.regiao, required this.altura});

  final String regiao;
  final double altura;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined,
                size: 30, color: AppColors.muted),
            const SizedBox(height: 8),
            Text(
              'Este turno não tem ponto de partida no mapa',
              textAlign: TextAlign.center,
              style: tsJakarta(11.5, FontWeight.w700, color: AppColors.text),
            ),
            const SizedBox(height: 3),
            Text(
              'Região informada: $regiao',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
