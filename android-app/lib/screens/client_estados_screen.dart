import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../services/api_service.dart';
import 'client_estados_viewer.dart';

class ClientEstadosScreen extends StatefulWidget {
  final List<Estado>  estados;
  final Future<void> Function() onRefresh;
  const ClientEstadosScreen({super.key, required this.estados, required this.onRefresh});
  @override State<ClientEstadosScreen> createState() => _ClientEstadosScreenState();
}

class _ClientEstadosScreenState extends State<ClientEstadosScreen> {
  static const _green = Color(0xFF1E6B2E);
  static const _gold  = Color(0xFFD4800A);

  List<Estado> get _estados => widget.estados;

  void _open(int index) async {
    if (_estados.isEmpty) return;
    await Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => FadeTransition(
        opacity: a,
        child: ClientEstadosViewer(estados: _estados, initialIndex: index),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    ));
    await widget.onRefresh();
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60)  return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24)    return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    if (_estados.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        color: _green,
        child: ListView(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('📖', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text('No hay estados disponibles',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              Text('Aquí aparecerán las novedades del negocio',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Actualizar'),
              ),
            ]),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: _green,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Story circles header
          SliverToBoxAdapter(child: _buildStoryRow()),

          // Grid of estados
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, 0, 12,
              MediaQuery.of(context).padding.bottom + 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _EstadoCard(
                  estado: _estados[i],
                  onTap:  () => _open(i),
                ),
                childCount: _estados.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.75,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryRow() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(children: [
          Icon(Icons.auto_stories_rounded, color: _gold, size: 18),
          SizedBox(width: 8),
          Text('Estados recientes',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A3009))),
        ]),
      ),
      SizedBox(
        height: 90,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _estados.length,
          itemBuilder: (_, i) {
            final e = _estados[i];
            return GestureDetector(
              onTap: () => _open(i),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                child: Column(children: [
                  Container(
                    width: 58, height: 58,
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [_gold, Color(0xFFFF9800)]),
                    ),
                    child: ClipOval(
                      child: e.mediaType == 'image'
                        ? CachedNetworkImage(
                            imageUrl: ApiService.estadoMediaUrl(e.filename),
                            httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF1A3009)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF1A3009),
                              child: const Icon(Icons.image, color: Colors.white30, size: 24)),
                          )
                        : Container(
                            color: const Color(0xFF1A3009),
                            child: const Icon(Icons.videocam, color: Colors.white, size: 24)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_formatTime(e.createdAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 9.5)),
                ]),
              ),
            );
          },
        ),
      ),
      const Divider(height: 20, indent: 16, endIndent: 16),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text('Publicaciones',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87)),
      ),
    ]);
  }
}

class _EstadoCard extends StatelessWidget {
  final Estado       estado;
  final VoidCallback onTap;
  const _EstadoCard({required this.estado, required this.onTap});

  static const _green = Color(0xFF1E6B2E);
  static const _gold  = Color(0xFFD4800A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Media
          Expanded(child: Stack(fit: StackFit.expand, children: [
            estado.mediaType == 'image'
              ? CachedNetworkImage(
                  imageUrl: ApiService.estadoMediaUrl(estado.filename),
                  httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: const Color(0xFFE8F5E9),
                    child: const Center(child: CircularProgressIndicator(
                      color: _green, strokeWidth: 2))),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFFE8F5E9),
                    child: const Icon(Icons.image_not_supported_rounded,
                      color: _green, size: 40)),
                )
              : Container(
                  color: Colors.black87,
                  child: const Center(child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 50))),
            // Gradient
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
                  stops: const [0.5, 1.0]),
              ),
            )),
            // Time badge
            Positioned(top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10)),
                child: Text(estado.timeAgo,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
              )),
            // Stats at bottom
            Positioned(bottom: 8, left: 8, right: 8,
              child: Row(children: [
                _StatBadge(icon: Icons.favorite_rounded, value: estado.heartCount, color: Colors.red.shade400),
                const SizedBox(width: 6),
                _StatBadge(icon: Icons.chat_bubble_rounded, value: estado.commentCount, color: Colors.blue.shade300),
              ])),
          ])),
          // Caption
          if (estado.caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(estado.caption!,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4)),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text('Ver estado', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ]),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final int      value;
  final Color    color;
  const _StatBadge({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text('$value', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );
}
