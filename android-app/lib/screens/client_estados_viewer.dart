import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../services/api_service.dart';
import 'client_product_detail.dart';

class ClientEstadosViewer extends StatefulWidget {
  final List<Estado> estados;
  final int initialIndex;
  // Solo para el rol admin viendo sus propios estados: permite deslizar
  // hacia arriba para ver quien dio like, igual que WhatsApp.
  final bool showLikesOnSwipeUp;
  const ClientEstadosViewer({
    super.key,
    required this.estados,
    this.initialIndex = 0,
    this.showLikesOnSwipeUp = false,
  });
  @override State<ClientEstadosViewer> createState() => _ClientEstadosViewerState();
}

class _ClientEstadosViewerState extends State<ClientEstadosViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _page;
  late final AnimationController _progressCtrl;
  late final AnimationController _heartBounceCtrl;

  int  _current   = 0;
  bool _paused    = false;
  bool _reacting  = false;
  List<Estado> _estados = [];

  // Estados pensados para verse con calma, no como un carrusel apurado
  // -- mucho mas lento que el default tipo Instagram/WhatsApp (5-7s).
  static const _autoDuration = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _estados = List.of(widget.estados);
    _page = PageController(initialPage: _current);
    _progressCtrl = AnimationController(vsync: this, duration: _autoDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _nextPage();
      });
    _heartBounceCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), lowerBound: 0.85, upperBound: 1.0)
      ..value = 1.0;
    _startProgress();
  }

  @override
  void dispose() {
    _page.dispose();
    _progressCtrl.dispose();
    _heartBounceCtrl.dispose();
    super.dispose();
  }

  void _startProgress() => _progressCtrl.forward(from: 0);

  void _pauseProgress() {
    if (_paused) return;
    _paused = true;
    _progressCtrl.stop();
  }

  void _resumeProgress() {
    if (!_paused) return;
    _paused = false;
    _progressCtrl.forward();
  }

  void _nextPage() {
    if (_current < _estados.length - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    } else {
      Navigator.pop(context);
    }
  }

  void _prevPage() {
    if (_current > 0) {
      _page.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    }
  }

  Future<void> _toggleHeart() async {
    if (_reacting) return;
    HapticFeedback.lightImpact();
    _heartBounceCtrl.forward(from: 0.85).then((_) => _heartBounceCtrl.value = 1.0);
    setState(() => _reacting = true);
    try {
      final result = await ApiService.reactToEstado(_estados[_current].id);
      if (mounted) setState(() {
        _estados[_current] = _estados[_current].copyWith(
          heartCount: result['heart_count'] as int,
          hasHearted: result['has_hearted'] as bool,
        );
      });
    } catch (_) {}
    if (mounted) setState(() => _reacting = false);
  }

  Future<void> _goToProduct() async {
    final e = _estados[_current];
    if (e.productId == null) return;
    _pauseProgress();
    try {
      final products = await ApiService.getProducts();
      final idx = products.indexWhere((p) => p.id == e.productId);
      if (idx < 0 || !mounted) { if (mounted) _resumeProgress(); return; }
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ClientProductDetail(product: products[idx], description: '')));
    } catch (_) {}
    if (mounted) _resumeProgress();
  }

  // Deslizar hacia arriba (solo dueño del estado, ej. admin) muestra quien
  // dio like -- igual que en WhatsApp.
  Future<void> _showLikes() async {
    final e = _estados[_current];
    _pauseProgress();
    List<Map<String, dynamic>> reactions = [];
    try { reactions = await ApiService.getEstadoReactions(e.id); } catch (_) {}
    if (!mounted) { _resumeProgress(); return; }
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Row(children: [
              const Icon(Icons.favorite, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text('${e.heartCount} me gusta',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            if (reactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nadie ha reaccionado todavía.',
                  style: TextStyle(color: Colors.white54)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: reactions.length,
                  itemBuilder: (_, i) {
                    final r = reactions[i];
                    final name = r['display_name'] as String? ?? r['username'] as String? ?? '?';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: scheme.primary.withValues(alpha: 0.25),
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14))),
                        const Icon(Icons.favorite, color: Colors.red, size: 14),
                      ]),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
    if (mounted) _resumeProgress();
  }

  @override
  Widget build(BuildContext context) {
    final e       = _estados[_current];
    final padBot  = MediaQuery.of(context).padding.bottom;
    final padTop  = MediaQuery.of(context).padding.top;
    final scheme  = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onLongPressStart: (_) {
          HapticFeedback.lightImpact();
          if (mounted) setState(() {});
          _pauseProgress();
        },
        onLongPressEnd: (_) {
          _resumeProgress();
          if (mounted) setState(() {});
        },
        onVerticalDragEnd: !widget.showLikesOnSwipeUp ? null : (details) {
          if ((details.primaryVelocity ?? 0) < -250) _showLikes();
        },
        child: Stack(children: [
          // ── Page view ─────────────────────────────────────────
          PageView.builder(
            controller: _page,
            itemCount: _estados.length,
            onPageChanged: (i) {
              if (mounted) setState(() => _current = i);
              _startProgress();
            },
            itemBuilder: (_, i) {
              final estado = _estados[i];
              return GestureDetector(
                onTapUp: (det) {
                  final w = MediaQuery.of(context).size.width;
                  if (det.globalPosition.dx < w * 0.35) _prevPage();
                  else if (det.globalPosition.dx > w * 0.65) _nextPage();
                },
                child: estado.mediaType == 'image'
                  ? CachedNetworkImage(
                      imageUrl: ApiService.estadoMediaUrl(estado.filename),
                      httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.image_not_supported, color: Colors.white38, size: 64)),
                    )
                  : Container(color: Colors.black87,
                      child: const Center(
                        child: Icon(Icons.videocam, color: Colors.white, size: 80))),
              );
            },
          ),

          // ── Pause overlay (WhatsApp style) ────────────────────
          if (_paused)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Icon(Icons.pause_circle_filled_rounded,
                    color: Colors.white54, size: 64),
                ),
              ),
            ),

          // ── Progress bars ──────────────────────────────────────
          Positioned(
            top: padTop + 6,
            left: 8, right: 8,
            child: Row(
              children: List.generate(_estados.length, (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: i < _current
                      ? Container(color: Colors.white)
                      : i == _current
                        ? AnimatedBuilder(
                            animation: _progressCtrl,
                            builder: (_, __) => LinearProgressIndicator(
                              value: _progressCtrl.value,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation(Colors.white),
                              minHeight: 3,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              )),
            ),
          ),

          // ── Header: store name + close ─────────────────────────
          Positioned(
            top: padTop + 16,
            left: 12, right: 12,
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primary,
                child: const Icon(Icons.storefront_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Concentrados Monserrath',
                  style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(e.timeAgo,
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: Colors.black38, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),

          // ── Bottom: caption + acciones ─────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent],
                  stops: const [0.0, 1.0],
                ),
              ),
              padding: EdgeInsets.fromLTRB(16, 36, 16, padBot + 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.caption != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(e.caption!,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.4,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
                  ),
                Row(children: [
                  // Corazón -- boton circular con rebote al tocar, mas
                  // grande y llamativo que el pill anterior.
                  GestureDetector(
                    onTap: _toggleHeart,
                    child: ScaleTransition(
                      scale: _heartBounceCtrl,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: e.hasHearted
                            ? Colors.red.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: e.hasHearted
                              ? Colors.red.shade300.withValues(alpha: 0.7)
                              : Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Icon(
                          e.hasHearted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: e.hasHearted ? Colors.red.shade400 : Colors.white,
                          size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${e.heartCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 16),
                  // Ir al producto (only if estado has linked product)
                  if (e.productId != null)
                    _ActionBtn(
                      onTap: _goToProduct,
                      icon: Icons.shopping_bag_outlined,
                      iconColor: scheme.secondary,
                      label: 'Ver producto',
                    ),
                  const Spacer(),
                  Text('${_current + 1} / ${_estados.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                if (widget.showLikesOnSwipeUp)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(child: Column(children: [
                      Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
                      Text('Desliza para ver quién dio like',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                    ])),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Action button widget ───────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color    iconColor;
  final String   label;
  const _ActionBtn({
    required this.onTap, required this.icon,
    required this.iconColor, required this.label,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 6),
        Text(label,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    ),
  );
}

