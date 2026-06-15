import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/estado.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class AdminEstadosScreen extends StatefulWidget {
  const AdminEstadosScreen({super.key});
  @override State<AdminEstadosScreen> createState() => _AdminEstadosScreenState();
}

class _AdminEstadosScreenState extends State<AdminEstadosScreen> {
  static const _green = Color(0xFF1E6B2E);
  List<Estado>   _estados  = [];
  List<Product>  _products = [];
  bool _loading   = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getEstados(),
        ApiService.getProducts(),
      ]);
      if (mounted) {
        _estados  = results[0] as List<Estado>;
        _products = (results[1] as List<Product>).where((p) => p.available).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'mov'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file     = result.files.first;
    final filePath = file.path;
    final bytes    = file.bytes;
    if (filePath == null && bytes == null) {
      _snack('No se pudo leer el archivo');
      return;
    }

    final ext = (file.extension ?? 'jpg').toLowerCase();
    const mimeMap = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'png': 'image/png',  'mp4': 'video/mp4',
      'mov': 'video/quicktime',
    };
    final mime = mimeMap[ext] ?? 'image/jpeg';

    final info = await _askCaptionAndProduct();
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      await ApiService.createEstado(
        filePath,
        caption:     info['caption'] as String?,
        bytes:       bytes,
        mimeType:    mime,
        productId:   info['product_id'] as int?,
        productName: info['product_name'] as String?,
      );
      await _load();
      if (mounted) _snack('Estado publicado (36h)', success: true);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<Map<String, dynamic>> _askCaptionAndProduct() async {
    final captionCtrl = TextEditingController();
    Product? selectedProduct;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nuevo estado'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: captionCtrl,
              decoration: const InputDecoration(
                labelText: 'Caption (opcional)',
                hintText: 'Escribe un texto...',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            if (_products.isNotEmpty)
              DropdownButtonFormField<Product>(
                value: selectedProduct,
                decoration: const InputDecoration(
                  labelText: 'Producto vinculado (opcional)',
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                hint: const Text('Sin producto'),
                items: [
                  const DropdownMenuItem<Product>(value: null, child: Text('Sin producto')),
                  ..._products.map((p) => DropdownMenuItem<Product>(
                    value: p,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (v) => setS(() => selectedProduct = v),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'caption':      captionCtrl.text.trim().isEmpty ? null : captionCtrl.text.trim(),
                'product_id':   selectedProduct?.id,
                'product_name': selectedProduct?.name,
              }),
              child: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
    return result ?? {'caption': null, 'product_id': null, 'product_name': null};
  }

  Future<void> _showLikes(Estado e) async {
    showDialog(
      context: context,
      builder: (_) => _LikesDialog(estadoId: e.id, heartCount: e.heartCount),
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
                  Text('Los estados duran 36 horas',
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
                      return GestureDetector(
                        onTap: () => _showLikes(e),
                        child: Card(
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
                                    const Icon(Icons.shopping_bag_outlined, color: Color(0xFFD4800A), size: 12),
                                    const SizedBox(width: 3),
                                    Expanded(child: Text(e.productName!,
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Color(0xFFD4800A), fontSize: 11))),
                                  ]),
                                const SizedBox(height: 2),
                                Row(children: [
                                  const Icon(Icons.favorite, color: Colors.red, size: 12),
                                  const SizedBox(width: 3),
                                  Text('${e.heartCount}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10)),
                                  const SizedBox(width: 8),
                                  Text(_timeLeft(e),
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10)),
                                ]),
                              ],
                            )),
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
                        ),
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

// ── Likes dialog ───────────────────────────────────────────────
class _LikesDialog extends StatefulWidget {
  final int estadoId;
  final int heartCount;
  const _LikesDialog({required this.estadoId, required this.heartCount});
  @override State<_LikesDialog> createState() => _LikesDialogState();
}

class _LikesDialogState extends State<_LikesDialog> {
  static const _green = Color(0xFF1E6B2E);
  List<Map<String, dynamic>> _reactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService.getEstadoReactions(widget.estadoId);
      if (mounted) setState(() { _reactions = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(children: [
      const Icon(Icons.favorite, color: Colors.red, size: 20),
      const SizedBox(width: 8),
      Text('${widget.heartCount} me gusta'),
    ]),
    content: SizedBox(
      width: 280,
      child: _loading
          ? const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: _green)))
          : _reactions.isEmpty
              ? const Text('Nadie ha reaccionado aún.',
                  style: TextStyle(color: Colors.grey))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _reactions.map((r) {
                    final name = r['display_name'] as String? ?? r['username'] as String? ?? '?';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFE8F5E9),
                          child: Text(name[0].toUpperCase(),
                            style: const TextStyle(color: _green, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Text(name, style: const TextStyle(fontSize: 14)),
                        const Spacer(),
                        const Icon(Icons.favorite, color: Colors.red, size: 14),
                      ]),
                    );
                  }).toList(),
                ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
    ],
  );
}
