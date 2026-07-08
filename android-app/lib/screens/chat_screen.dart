import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';

class ChatScreen extends StatefulWidget {
  final String  phone;
  final String  name;
  final String? profilePicUrl;

  const ChatScreen({
    super.key,
    required this.phone,
    required this.name,
    this.profilePicUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Controllers
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  // State
  List<Message> _messages = [];
  bool _sending    = false;
  bool _recording  = false;
  bool _hasText    = false;
  bool _loadError  = false;
  bool _loadingFirst = true;
  int  _recSeconds = 0;
  Timer? _pollTimer;
  Timer? _recTimer;

  // Audio
  final _player  = AudioPlayer();
  final _recorder = AudioRecorder();
  int?   _playingId;
  PlayerState _playerState = PlayerState.stopped;
  final Map<int, String>  _localAudioCache = {};
  final Map<int, bool>    _loadingAudio    = {};
  final Map<int, Uint8List> _imageCache    = {};

  StreamSubscription? _playerStateSub;
  StreamSubscription? _playerCompleteSub;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _playerStateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playingId = null; _playerState = PlayerState.stopped; });
    });
    _load(markRead: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _recTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _player.dispose();
    _recorder.dispose();
    _playerStateSub?.cancel();
    _playerCompleteSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool markRead = false}) async {
    try {
      final msgs = await ApiService.getMessages(widget.phone);
      if (mounted) {
        setState(() { _messages = msgs; _loadError = false; _loadingFirst = false; });
        _scrollDown();
      }
      if (markRead) ApiService.markConversationRead(widget.phone).catchError((_) {});
    } catch (_) {
      // Silencioso en el poll de fondo (cada 2s reintenta solo) -- pero si es
      // la carga inicial o ya llevamos varios fallos, se lo mostramos al
      // usuario en vez de dejarlo mirando una pantalla vacía sin explicación.
      if (mounted && (_loadingFirst || _messages.isEmpty)) {
        setState(() { _loadError = true; _loadingFirst = false; });
      }
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── Send text ────────────────────────────────────────────
  Future<void> _sendText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() => _sending = true);
    try {
      await ApiService.sendWhatsAppMessage(widget.phone, text);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error enviando mensaje')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Send image ───────────────────────────────────────────
  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _sending = true);
      final bytes = await file.readAsBytes();
      await ApiService.sendMediaMessage(widget.phone, bytes, file.name, 'image');
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error enviando imagen')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Send video ───────────────────────────────────────────
  Future<void> _pickAndSendVideo() async {
    final picker = ImagePicker();
    try {
      final file = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (file == null) return;
      setState(() => _sending = true);
      final bytes = await file.readAsBytes();
      await ApiService.sendMediaMessage(widget.phone, bytes, file.name, 'video');
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error enviando video')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Send document ────────────────────────────────────────
  Future<void> _pickAndSendDocument() async {
    try {
      // withData: true fuerza a leer los bytes en memoria -- en Web no hay
      // ruta de archivo real (path siempre null), solo bytes.
      final result = await FilePicker.platform.pickFiles(withData: true);
      final picked = result?.files.single;
      if (picked?.bytes == null) return;
      setState(() => _sending = true);
      await ApiService.sendMediaMessage(widget.phone, picked!.bytes!, picked.name, 'document');
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error enviando documento')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Audio recording ──────────────────────────────────────
  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    // El MediaRecorder del navegador no soporta aac/m4a (Chrome/Firefox
    // solo graban en contenedor webm/opus) -- con aacLc en Web el propio
    // record_web tira "not supported" antes de arrancar. En nativo (Android/
    // escritorio) aacLc si funciona y da un .m4a real.
    final config = kIsWeb
      ? const RecordConfig(encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 44100)
      : const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100);
    String path = 'audio';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    await _recorder.start(config, path: path);
    setState(() { _recording = true; _recSeconds = 0; });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSeconds++);
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recTimer?.cancel();
    // En Web esto es una blob: URL (no una ruta de dart:io) -- en nativo es
    // la ruta real del archivo grabado.
    final result = await _recorder.stop();
    setState(() { _recording = false; _recSeconds = 0; });
    if (result == null) return;
    setState(() => _sending = true);
    try {
      Uint8List bytes;
      String filename;
      if (kIsWeb) {
        bytes    = (await http.get(Uri.parse(result))).bodyBytes;
        filename = 'audio_${DateTime.now().millisecondsSinceEpoch}.weba';
      } else {
        bytes    = await File(result).readAsBytes();
        filename = result.split('/').last;
      }
      await ApiService.sendMediaMessage(widget.phone, bytes, filename, 'audio');
      await _load();
      if (!kIsWeb) { try { File(result).deleteSync(); } catch (_) {} }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error enviando audio')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    await _recorder.stop();
    setState(() { _recording = false; _recSeconds = 0; });
  }

  // ── Audio playback ───────────────────────────────────────
  Future<void> _toggleAudio(Message msg) async {
    final msgId = msg.id ?? 0;
    final mediaUrl = msg.mediaUrl;
    if (mediaUrl == null) return;

    if (_playingId == msgId && _playerState == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (_playingId == msgId && _playerState == PlayerState.paused) {
      await _player.resume();
      return;
    }

    // Stop any playing audio first
    await _player.stop();

    // Get local path (download if needed)
    String? localPath = _localAudioCache[msgId];
    if (localPath == null || !File(localPath).existsSync()) {
      setState(() => _loadingAudio[msgId] = true);
      try {
        final bytes = await ApiService.downloadMedia(mediaUrl);
        if (bytes != null) {
          final dir  = await getTemporaryDirectory();
          final ext  = mediaUrl.contains('.') ? mediaUrl.split('.').last.split('?').first : 'ogg';
          final file = File('${dir.path}/audio_$msgId.$ext');
          await file.writeAsBytes(bytes);
          localPath = file.path;
          _localAudioCache[msgId] = localPath;
        }
      } catch (_) {}
      if (mounted) setState(() => _loadingAudio.remove(msgId));
    }

    if (localPath == null) return;
    setState(() => _playingId = msgId);
    await _player.play(DeviceFileSource(localPath));
  }

  // ── Image viewer ─────────────────────────────────────────
  Future<void> _viewImage(Message msg) async {
    final msgId = msg.id ?? 0;
    Uint8List? bytes = _imageCache[msgId];
    if (bytes == null && msg.mediaUrl != null) {
      bytes = await ApiService.downloadMedia(msg.mediaUrl!);
      if (bytes != null && mounted) setState(() => _imageCache[msgId] = bytes!);
    }
    if (bytes == null || !mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          Center(child: InteractiveViewer(child: Image.memory(bytes!, fit: BoxFit.contain))),
          Positioned(top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            )),
        ]),
      ),
    );
  }

  Future<Uint8List?> _loadImage(Message msg) async {
    final msgId = msg.id ?? 0;
    if (_imageCache.containsKey(msgId)) return _imageCache[msgId];
    if (msg.mediaUrl == null) return null;
    final bytes = await ApiService.downloadMedia(msg.mediaUrl!);
    if (bytes != null && mounted) setState(() => _imageCache[msgId] = bytes);
    return bytes;
  }

  // ── Video playback ───────────────────────────────────────
  bool _videoDownloading = false;

  Future<void> _playVideo(Message msg) async {
    if (msg.mediaUrl == null || _videoDownloading) return;
    setState(() => _videoDownloading = true);
    try {
      final bytes = await ApiService.downloadMedia(msg.mediaUrl!);
      if (bytes == null) throw Exception('sin datos');
      final dir  = await getTemporaryDirectory();
      final ext  = msg.mediaUrl!.contains('.') ? msg.mediaUrl!.split('.').last.split('?').first : 'mp4';
      final file = File('${dir.path}/video_${msg.id}.$ext');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => _VideoPlayerScreen(path: file.path),
        fullscreenDialog: true,
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar el video')));
    } finally {
      if (mounted) setState(() => _videoDownloading = false);
    }
  }

  // ── Documento ────────────────────────────────────────────
  bool _docDownloading = false;

  Future<void> _openDocument(Message msg) async {
    if (msg.mediaUrl == null || _docDownloading) return;
    setState(() => _docDownloading = true);
    try {
      final bytes = await ApiService.downloadMedia(msg.mediaUrl!);
      if (bytes == null) throw Exception('sin datos');
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/${msg.documentFileName}');
      await file.writeAsBytes(bytes);
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Documento guardado: ${file.path}')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el documento')));
    } finally {
      if (mounted) setState(() => _docDownloading = false);
    }
  }

  // ── Phone call ───────────────────────────────────────────
  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: '+57${widget.phone}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ── Format ───────────────────────────────────────────────
  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt);
  }

  String _formatRecDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // ── Message bubbles ──────────────────────────────────────
  Widget _buildBubble(Message msg) {
    final isOut       = msg.isOutbound;
    final bgColor     = isOut ? const Color(0xFFDCF8C6) : Colors.white;
    final borderRadius = BorderRadius.only(
      topLeft:     const Radius.circular(16),
      topRight:    const Radius.circular(16),
      bottomLeft:  Radius.circular(isOut ? 16 : 4),
      bottomRight: Radius.circular(isOut ? 4 : 16),
    );

    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Content
            Padding(
              padding: EdgeInsets.fromLTRB(
                10, 8, 10,
                msg.isMediaMsg ? 4 : 2,
              ),
              child: msg.isAudio
                ? _buildAudioContent(msg)
                : msg.isImage
                  ? _buildImageContent(msg)
                  : msg.isVideo
                    ? _buildVideoContent(msg)
                    : msg.isDocument
                      ? _buildDocumentContent(msg)
                      : Text(msg.content, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A))),
            ),
            // Time + status
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_formatTime(msg.createdAt),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
                if (isOut) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.sent == 1 ? Icons.done_all : Icons.done,
                    size: 12,
                    color: msg.sent == 1 ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioContent(Message msg) {
    final msgId    = msg.id ?? 0;
    final isPlaying = _playingId == msgId && _playerState == PlayerState.playing;
    final isLoading = _loadingAudio[msgId] == true;
    final scheme = Theme.of(context).colorScheme;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: () => _toggleAudio(msg),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: isLoading
            ? Padding(padding: const EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
            : Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: scheme.primary, size: 24),
        ),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.graphic_eq, color: scheme.primary, size: 20),
        const SizedBox(height: 2),
        Text('Mensaje de voz', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]),
      const SizedBox(width: 8),
    ]);
  }

  Widget _buildImageContent(Message msg) {
    final msgId = msg.id ?? 0;
    final cached = _imageCache[msgId];
    final screenW = MediaQuery.of(context).size.width;
    final imgW = (screenW * 0.65).clamp(160.0, 260.0);
    final imgH = imgW * 0.75;
    return GestureDetector(
      onTap: () => _viewImage(msg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: cached != null
          ? Image.memory(cached, width: imgW, height: imgH, fit: BoxFit.cover)
          : FutureBuilder<Uint8List?>(
              future: _loadImage(msg),
              builder: (ctx, snap) {
                if (snap.hasData && snap.data != null)
                  return Image.memory(snap.data!, width: imgW, height: imgH, fit: BoxFit.cover);
                return Container(
                  width: imgW, height: imgH,
                  color: Colors.grey.shade200,
                  child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
                );
              },
            ),
      ),
    );
  }

  Widget _buildVideoContent(Message msg) {
    final screenW = MediaQuery.of(context).size.width;
    final w = (screenW * 0.65).clamp(160.0, 260.0);
    return GestureDetector(
      onTap: () => _playVideo(msg),
      child: Container(
        width: w, height: w * 0.75,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: Center(
          child: _videoDownloading
            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            : const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44),
        ),
      ),
    );
  }

  Widget _buildDocumentContent(Message msg) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openDocument(msg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: _docDownloading
              ? Padding(padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
              : Icon(Icons.insert_drive_file_rounded, color: scheme.primary, size: 22),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(msg.documentFileName,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
            overflow: TextOverflow.ellipsis, maxLines: 2)),
        ]),
      ),
    );
  }

  // ── Input bar ────────────────────────────────────────────
  Widget _buildInputBar() {
    final scheme = Theme.of(context).colorScheme;
    if (_recording) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
        child: Row(children: [
          GestureDetector(
            onTap: _cancelRecording,
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Row(children: [
            Container(width: 10, height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(_formatRecDuration(_recSeconds),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.primary)),
            const Spacer(),
            const Text('Grabando…', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ])),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _stopAndSendRecording,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ]),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(left: 6, right: 8, top: 6, bottom: 6),
      child: Row(children: [
        // Adjuntar (foto / video / documento)
        PopupMenuButton<String>(
          icon: const Icon(Icons.attach_file_rounded, color: Colors.grey),
          tooltip: 'Adjuntar',
          enabled: !_sending,
          onSelected: (v) {
            if (v == 'image') _pickAndSendImage();
            if (v == 'video') _pickAndSendVideo();
            if (v == 'document') _pickAndSendDocument();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'image', child: Row(children: [
              Icon(Icons.image_rounded, color: Colors.grey), SizedBox(width: 8), Text('Foto'),
            ])),
            PopupMenuItem(value: 'video', child: Row(children: [
              Icon(Icons.videocam_rounded, color: Colors.grey), SizedBox(width: 8), Text('Video'),
            ])),
            PopupMenuItem(value: 'document', child: Row(children: [
              Icon(Icons.insert_drive_file_rounded, color: Colors.grey), SizedBox(width: 8), Text('Documento'),
            ])),
          ],
        ),
        // Text field
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: TextField(
              controller: _ctrl,
              maxLines: 4, minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Escribe un mensaje…',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Send / Mic button
        GestureDetector(
          onTap: _sending ? null : (_hasText ? _sendText : _startRecording),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: _sending
              ? const Padding(padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(
                  _hasText ? Icons.send_rounded : Icons.mic_rounded,
                  color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── AppBar ───────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
      titleSpacing: 0,
      leading: BackButton(color: Colors.white, onPressed: () => Navigator.pop(context)),
      title: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white24,
          backgroundImage: widget.profilePicUrl != null && widget.profilePicUrl!.isNotEmpty
              ? CachedNetworkImageProvider(widget.profilePicUrl!)
              : null,
          child: widget.profilePicUrl == null || widget.profilePicUrl!.isEmpty
              ? Text(widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              overflow: TextOverflow.ellipsis),
            Text('+57${widget.phone}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        )),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.call, color: Colors.white),
          tooltip: 'Llamar',
          onPressed: _call,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) async {
            if (v == 'delete') {
              final ok = await showDialog<bool>(context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Borrar conversación'),
                  content: const Text('¿Borrar todos los mensajes de esta conversación?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Borrar'),
                    ),
                  ],
                ));
              if (ok == true) {
                await ApiService.deleteConversation(widget.phone);
                if (mounted) Navigator.pop(context);
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Borrar conversación', style: TextStyle(color: Colors.red)),
              ])),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EAD6),
      appBar: _buildAppBar(),
      body: Column(children: [
        Expanded(
          child: _loadError && _messages.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 40, color: Colors.grey),
                const SizedBox(height: 10),
                const Text('No se pudieron cargar los mensajes', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _load(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reintentar'),
                ),
              ]))
            : _messages.isEmpty
            ? const EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'Sin mensajes aún')
            : ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) => _buildBubble(_messages[_messages.length - 1 - i]),
              ),
        ),
        _buildInputBar(),
      ]),
    );
  }
}

/// Reproductor de video de pantalla completa mínimo (play/pausa + barra de
/// progreso) -- suficiente para revisar un video recibido/enviado por el
/// bot, sin depender de un paquete de UI extra (chewie).
class _VideoPlayerScreen extends StatefulWidget {
  final String path;
  const _VideoPlayerScreen({required this.path});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _ready
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(alignment: Alignment.bottomCenter, children: [
                VideoPlayer(_controller),
                VideoProgressIndicator(_controller, allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Colors.white)),
              ]),
            )
          : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButton: _ready
        ? FloatingActionButton(
            backgroundColor: Colors.white,
            onPressed: () => setState(() =>
              _controller.value.isPlaying ? _controller.pause() : _controller.play()),
            child: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.black),
          )
        : null,
    );
  }
}
