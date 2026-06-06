import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../services/api_service.dart';

class AdminEstadosScreen extends StatefulWidget {
  const AdminEstadosScreen({super.key});
  @override State<AdminEstadosScreen> createState() => _AdminEstadosScreenState();
}

class _AdminEstadosScreenState extends State<AdminEstadosScreen> {
  static const _green = Color(0xFF1E6B2E);
  List<Estado> _estados = [];
  bool _loading = true;
  bool _uploading = false;

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

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'mov'],
    );
    if (result == null || result.files.isEmpty) return;

    final caption = await _askCaption();
    setState(() => _uploading = true);
    try {
      await ApiService.createEstado(result.files.first.path!, caption: caption);
      await _load();
      if (mounted) _snack('Estado publicado (32h)', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _askCaption() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Caption (opcional)'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Escribe un texto...'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Omitir')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Estado e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar estado'),
        content: const Text('¿Eliminar este estado permanentemente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteEstado(e.id);
      await _load();
      if (mounted) _snack('Estado eliminado', success: true);
    } catch (ex) {
      if (mounted) _snack(ex.toString().replaceAll('Exception: ', ''));
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? _green : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _timeLeft(Estado e) {
    final diff = e.expiresAt.difference(DateTime.now());
    if (diff.inHours >= 1) return '${diff.inHours}h restantes';
    return '${diff.inMinutes}min restantes';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _estados.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('📸', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  const Text('No hay estados activos',
                    style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text('Los estados duran 32 horas',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _green,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
                      childAspectRatio: 0.75),
                    itemCount: _estados.length,
                    itemBuilder: (_, i) {
                      final e = _estados[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Stack(children: [
                          // Media preview
                          Positioned.fill(
                            child: e.mediaType == 'image'
                                ? CachedNetworkImage(
                                    imageUrl: ApiService.estadoMediaUrl(e.filename),
                                    httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 48)),
                                  )
                                : Container(
                                    color: Colors.black87,
                                    child: const Icon(Icons.videocam, color: Colors.white, size: 48)),
                          ),
                          // Gradient overlay
                          Positioned.fill(child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                              ),
                            ),
                          )),
                          // Caption + time
                          Positioned(left: 8, right: 8, bottom: 8, child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.caption != null)
                                Text(e.caption!,
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(_timeLeft(e),
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10)),
                            ],
                          )),
                          // Delete button
                          Positioned(top: 4, right: 4, child: GestureDetector(
                            onTap: () => _delete(e),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          )),
                        ]),
                      );
                    },
                  ),
                ),

      if (_uploading)
        const Positioned.fill(child: ColoredBox(
          color: Colors.black26,
          child: Center(child: CircularProgressIndicator(color: _green)),
        )),

      Positioned(
        bottom: 20, right: 16,
        child: FloatingActionButton.extended(
          onPressed: _uploading ? null : _pickAndUpload,
          backgroundColor: _green,
          icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
          label: const Text('Nuevo estado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}
