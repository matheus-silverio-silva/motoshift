import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';

class MapaRaio extends StatelessWidget {
  const MapaRaio({
    required this.centro,
    required this.raioKm,
    this.height = 180,
    super.key,
  });

  final LatLng centro;
  final double raioKm;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: centro,
            initialZoom: _zoomParaRaio(raioKm),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.motoshift.app',
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: centro,
                  radius: raioKm * 1000,
                  useRadiusInMeter: true,
                  color: AppColors.teal.withOpacity(0.15),
                  borderColor: AppColors.teal,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: centro,
                  width: 32,
                  height: 32,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.store_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _zoomParaRaio(double km) {
    if (km <= 2) return 14;
    if (km <= 5) return 13;
    if (km <= 10) return 12;
    return 11;
  }
}
