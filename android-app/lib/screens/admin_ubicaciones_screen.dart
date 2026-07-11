import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../services/api_service.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

/// Listado de ubicación de trabajadores/admin -- solo admin la ve (mismo
/// alcance que el backend: GET /api/staff-locations requiere adminAuth).
/// Nunca hay forma de que un cliente llegue a esta pantalla ni a sus datos.
class AdminUbicacionesScreen extends StatefulWidget {
  const AdminUbicacionesScreen({super.key});
  @override State<AdminUbicacionesScreen> createState() => _AdminUbicacionesScreenState();
}

class _AdminUbicacionesScreenState extends State<AdminUbicacionesScreen> {
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;
  final _mapController = MapController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Mismo cadencia que el reporte del celular (cada 30s) -- el mapa se
    // siente "en vivo" sin machacar al servidor con polling mas seguido.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_staff.isEmpty) setState(() => _loading = true);
    try {
      final fresh = await ApiService.getStaffLocations();
      if (mounted) setState(() => _staff = fresh);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
  }

  List<ll.LatLng> get _points => _staff
      .where((s) => s['lat'] != null)
      .map((s) => ll.LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()))
      .toList();

  void _fitBounds() {
    final points = _points;
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
    } else {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ));
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return 'sin datos aún';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '-';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1)  return 'ahora mismo';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  Future<void> _openDetail(Map<String, dynamic> s) async {
    Map<String, dynamic>? detail;
    try { detail = await ApiService.getStaffLocationDetail(s['id'] as int); } catch (_) {}
    if (!mounted) return;
    final history = (detail?['history'] as List? ?? []).cast<Map<String, dynamic>>();
    final lastLogin = detail?['last_login'] as Map<String, dynamic>?;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['display_name'] as String? ?? s['username'] as String,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('@${s['username']} · ${s['role']}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            if (lastLogin != null) ...[
              Row(children: [
                const Icon(Icons.login_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text('Entrada: ${lastLogin['logged_in_at'] ?? '-'}', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.phone_android_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(child: Text(lastLogin['device_info'] as String? ?? 'Dispositivo desconocido',
                  style: const TextStyle(fontSize: 12))),
              ]),
            ],
            const SizedBox(height: 16),
            const Text('Historial de ubicaciones recientes', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: history.isEmpty
                ? const Center(child: Text('Sin ubicaciones registradas todavía', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: history.length,
                    itemBuilder: (_, i) {
                      final h = history[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text('${h['lat']}, ${h['lng']}'),
                        subtitle: Text('${h['recorded_at']}'),
                      );
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildMap(ColorScheme scheme) {
    final points = _points;
    if (points.isEmpty) {
      return Container(
        height: 220,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.map_outlined, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Sin ubicaciones activas', style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
    }
    final markers = _staff.where((s) => s['lat'] != null).map((s) {
      final point = ll.LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble());
      return Marker(
        point: point,
        width: 42,
        height: 42,
        child: GestureDetector(
          onTap: () => _openDetail(s),
          child: Icon(Icons.location_on_rounded, color: scheme.primary, size: 42,
            shadows: const [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
        ),
      );
    }).toList();

    return Container(
      height: 220,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: points.first, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.concentrados.monserrath.app',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return Center(child: CircularProgressIndicator(color: scheme.primary));

    return Column(children: [
      _buildMap(scheme),
      Expanded(
        child: _staff.isEmpty
          ? const EmptyState(icon: Icons.location_off_outlined, title: 'Sin trabajadores registrados')
          : RefreshIndicator(
              onRefresh: _load,
              color: scheme.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _staff.length,
                itemBuilder: (_, i) {
                  final s = _staff[i];
                  final hasLocation = s['lat'] != null;
                  return GestureDetector(
                    onTap: () => _openDetail(s),
                    child: AppCard(child: Row(children: [
                      Icon(hasLocation ? Icons.location_on_rounded : Icons.location_off_outlined,
                        color: hasLocation ? scheme.primary : Colors.grey.shade400),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['display_name'] as String? ?? s['username'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(hasLocation ? 'Última ubicación ${_timeAgo(s['last_seen_at'] as String?)}' : 'Aún no ha compartido ubicación',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ])),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                    ])),
                  );
                },
              ),
            ),
      ),
    ]);
  }
}
