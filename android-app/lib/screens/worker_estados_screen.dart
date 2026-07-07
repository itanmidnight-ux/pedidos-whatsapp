import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';

class WorkerEstadosScreen extends StatefulWidget {
  const WorkerEstadosScreen({super.key});
  @override State<WorkerEstadosScreen> createState() => _WorkerEstadosScreenState();
}

class _WorkerEstadosScreenState extends State<WorkerEstadosScreen> {
  List<Estado> _estados = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getEstados();
      if (mounted) setState(() => _estados = list);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _timeLeft(Estado e) {
    final diff = e.expiresAt.difference(DateTime.now());
    if (diff.inHours >= 1) return '${diff.inHours}h restantes';
    return '${diff.inMinutes}min restantes';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return Center(child: CircularProgressIndicator(color: scheme.primary));

    if (_estados.isEmpty) {
      return const EmptyState(
        emoji: '📸',
        title: 'No hay estados activos',
        subtitle: 'El administrador publicará estados aquí',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: scheme.primary,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
          childAspectRatio: 0.75),
        itemCount: _estados.length,
        itemBuilder: (_, i) {
          final e = _estados[i];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Positioned.fill(
                child: e.mediaType == 'image'
                    ? CachedNetworkImage(
                        imageUrl: ApiService.estadoMediaUrl(e.filename),
                        httpHeaders: ApiService.imageHeaders,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 48)),
                      )
                    : Container(
                        color: Colors.black87,
                        child: const Icon(Icons.videocam, color: Colors.white, size: 48)),
              ),
              Positioned.fill(child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                  ),
                ),
              )),
              Positioned(left: 8, right: 8, bottom: 8, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e.caption != null)
                    Text(e.caption!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  if (e.productName != null)
                    Row(children: [
                      Icon(Icons.shopping_bag_outlined, color: scheme.secondary, size: 12),
                      const SizedBox(width: 3),
                      Expanded(child: Text(e.productName!,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.secondary, fontSize: 11))),
                    ]),
                  const SizedBox(height: 2),
                  Text(_timeLeft(e),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10)),
                ],
              )),
            ]),
          );
        },
      ),
    );
  }
}
