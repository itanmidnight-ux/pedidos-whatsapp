import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../services/api_service.dart';

class ClientEstadosViewer extends StatefulWidget {
  final List<Estado> estados;
  final int initialIndex;
  const ClientEstadosViewer({super.key, required this.estados, this.initialIndex = 0});
  @override State<ClientEstadosViewer> createState() => _ClientEstadosViewerState();
}

class _ClientEstadosViewerState extends State<ClientEstadosViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _page;
  late final AnimationController _progressCtrl;

  int  _current   = 0;
  bool _paused    = false;
  bool _reacting  = false;
  bool _replying  = false;
  List<Estado> _estados = [];
  final _replyCtrl   = TextEditingController();
  final _replyFocus  = FocusNode();

  static const _autoDuration = Duration(seconds: 15);
  static const _green = Color(0xFF1A7A35);

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _estados = List.of(widget.estados);
    _page = PageController(initialPage: _current);
    _progressCtrl = AnimationController(vsync: this, duration: _autoDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_replying) _nextPage();
      });
    _startProgress();

    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _pauseProgress();
        if (mounted) setState(() => _replying = true);
      } else {
        if (mounted) setState(() => _replying = false);
        _resumeProgress();
      }
    });
  }

  @override
  void dispose() {
    _page.dispose();
    _progressCtrl.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
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

  void _showComments() async {
    _pauseProgress();
    setState(() => _replying = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(estadoId: _estados[_current].id),
    );
    try {
      final comments = await ApiService.getEstadoComments(_estados[_current].id);
      if (mounted) setState(() {
        _estados[_current] = _estados[_current].copyWith(commentCount: comments.length);
      });
    } catch (_) {}
    if (mounted) setState(() => _replying = false);
    _resumeProgress();
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    _replyCtrl.clear();
    _replyFocus.unfocus();

    HapticFeedback.lightImpact();
    String reply;
    try {
      reply = await ApiService.sendAppMessage(text);
    } catch (_) {
      reply = '✅ Mensaje enviado. Te responderemos pronto.';
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded, color: _green, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Mensaje enviado',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(reply,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Entendido'),
              )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e       = _estados[_current];
    final padBot  = MediaQuery.of(context).padding.bottom;
    final padTop  = MediaQuery.of(context).padding.top;

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
                  if (_replying) return;
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
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF1A7A35),
                child: Text('🌾', style: TextStyle(fontSize: 18)),
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

          // ── Bottom: caption + actions + reply ─────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Caption + action buttons
                if (!_replying)
                  Container(
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
                    padding: const EdgeInsets.fromLTRB(16, 36, 16, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (e.caption != null)
                        Text(e.caption!,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 14, height: 1.4,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
                      const SizedBox(height: 12),
                      Row(children: [
                        // Heart
                        _ActionBtn(
                          onTap: _toggleHeart,
                          icon: e.hasHearted
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                          iconColor: e.hasHearted
                            ? Colors.red.shade300 : Colors.white,
                          label: '${e.heartCount}',
                          active: e.hasHearted,
                          activeColor: Colors.red.withValues(alpha: 0.25),
                        ),
                        const SizedBox(width: 10),
                        // Comments
                        _ActionBtn(
                          onTap: _showComments,
                          icon: Icons.chat_bubble_outline_rounded,
                          iconColor: Colors.white,
                          label: '${e.commentCount}',
                        ),
                        const Spacer(),
                        Text('${_current + 1} / ${_estados.length}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    ]),
                  ),

                // ── Reply bar (WhatsApp style) ───────────────────
                Container(
                  color: Colors.black.withValues(alpha: _replying ? 0.95 : 0.6),
                  padding: EdgeInsets.fromLTRB(
                    12, 8, 12, padBot + 8),
                  child: Row(children: [
                    Expanded(child: TextField(
                      controller: _replyCtrl,
                      focusNode:  _replyFocus,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje o pide un producto...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.12),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35))),
                      ),
                    )),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendReply,
                      child: Container(
                        width: 44, height: 44,
                        decoration: const BoxDecoration(
                          color: _green, shape: BoxShape.circle),
                        child: const Icon(
                          Icons.send_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ]),
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
  final bool     active;
  final Color?   activeColor;
  const _ActionBtn({
    required this.onTap, required this.icon,
    required this.iconColor, required this.label,
    this.active = false, this.activeColor,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? activeColor : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: active
            ? Colors.red.shade300.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 6),
        Text(label,
          style: TextStyle(
            color: active ? Colors.red.shade200 : Colors.white,
            fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    ),
  );
}

// ── Comments bottom sheet ──────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  final int estadoId;
  const _CommentsSheet({required this.estadoId});
  @override State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const _green = Color(0xFF1E6B2E);
  List<Map<String, dynamic>> _comments = [];
  bool _loading  = true;
  bool _sending  = false;
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _ctrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final c = await ApiService.getEstadoComments(widget.estadoId);
      if (mounted) setState(() { _comments = c; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ApiService.addEstadoComment(widget.estadoId, text);
      _ctrl.clear();
      await _load();
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
      }
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        const Text('Comentarios',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const Divider(height: 16),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _comments.isEmpty
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('💬', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text('Sé el primero en comentar',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              ])
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _comments.length,
                itemBuilder: (_, i) {
                  final c    = _comments[i];
                  final name = c['display_name'] as String? ?? c['username'] as String? ?? '?';
                  final text = c['comment'] as String? ?? '';
                  final time = c['created_at'] as String?;
                  DateTime? dt;
                  try { dt = time != null ? DateTime.parse(time).toLocal() : null; } catch (_) {}
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFE8F5E9),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: _green, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                          if (dt != null) ...[
                            const SizedBox(width: 8),
                            Text(_fmtTime(dt),
                              style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 11)),
                          ],
                        ]),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.only(
                              topRight:    Radius.circular(14),
                              bottomLeft:  Radius.circular(14),
                              bottomRight: Radius.circular(14),
                            ),
                          ),
                          child: Text(text,
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                        ),
                      ])),
                    ]),
                  );
                },
              ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            12, 8, 12,
            MediaQuery.of(context).viewInsets.bottom + 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Escribe un comentario...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  color: _green, shape: BoxShape.circle),
                child: _sending
                  ? const Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }
}
