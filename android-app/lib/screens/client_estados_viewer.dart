import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../services/api_service.dart';

class ClientEstadosViewer extends StatefulWidget {
  final List<Estado> estados;
  final int initialIndex;
  const ClientEstadosViewer({super.key, required this.estados, this.initialIndex = 0});
  @override State<ClientEstadosViewer> createState() => _ClientEstadosViewerState();
}

class _ClientEstadosViewerState extends State<ClientEstadosViewer> {
  late PageController _ctrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final e = widget.estados[_current];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Page view
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.estados.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) {
            final estado = widget.estados[i];
            return GestureDetector(
              onTapUp: (details) {
                final w = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < w / 2) {
                  if (_current > 0) _ctrl.previousPage(
                    duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
                } else {
                  if (_current < widget.estados.length - 1) _ctrl.nextPage(
                    duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
                  else Navigator.pop(context);
                }
              },
              child: estado.mediaType == 'image'
                  ? CachedNetworkImage(
                      imageUrl: ApiService.estadoMediaUrl(estado.filename),
                      httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.image_not_supported, color: Colors.white, size: 64)),
                    )
                  : Container(
                      color: Colors.black87,
                      child: const Center(
                        child: Icon(Icons.videocam, color: Colors.white, size: 80))),
            );
          },
        ),

        // Progress indicators
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8, right: 8,
          child: Row(
            children: List.generate(widget.estados.length, (i) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 2.5,
                decoration: BoxDecoration(
                  color: i <= _current ? Colors.white : Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
        ),

        // Close button
        Positioned(
          top: MediaQuery.of(context).padding.top + 20,
          right: 12,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ),

        // Caption overlay at bottom
        if (e.caption != null)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
              child: Text(
                e.caption!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ]),
    );
  }
}
