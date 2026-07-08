import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/app_provider.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/empty_state.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {

  // ── Agregar producto ──────────────────────────────────────
  void _showAddProduct() {
    final nameCtrl  = TextEditingController();
    final priceCtrl = TextEditingController();
    final picker    = ImagePicker();
    final scheme    = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        XFile? pickedImage;
        return StatefulBuilder(
          builder: (ctx, setModal) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Nuevo Producto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.primary)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del producto',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Precio', border: OutlineInputBorder(), prefixText: '\$'),
                keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              const Text('Foto del producto',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                  if (img != null) setModal(() => pickedImage = img);
                },
                child: Container(
                  width: double.infinity, height: 130,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: pickedImage != null ? scheme.primary : Colors.grey.shade300,
                      width: pickedImage != null ? 2 : 1)),
                  child: pickedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(File(pickedImage!.path), fit: BoxFit.cover))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_rounded, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 6),
                        Text('Toca para agregar foto',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      ]),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Guardar Producto',
                icon: Icons.check_rounded,
                onPressed: () async {
                  String _np(String s) {
                    s = s.trim();
                    if (s.contains(',') && s.contains('.')) {
                      return s.replaceAll('.', '').replaceAll(',', '.');
                    } else if (s.contains(',')) {
                      final p = s.split(',');
                      return (p.length == 2 && p[1].length <= 2)
                          ? s.replaceAll(',', '.') : s.replaceAll(',', '');
                    } else if (s.contains('.')) {
                      final p = s.split('.');
                      if (p.length == 2 && p[1].length == 3) return s.replaceAll('.', '');
                    }
                    return s;
                  }
                  final price = double.tryParse(_np(priceCtrl.text));
                  if (nameCtrl.text.trim().isEmpty || price == null) return;
                  final capturedName  = nameCtrl.text.trim();
                  final capturedImage = pickedImage;
                  Navigator.pop(ctx);
                  try {
                    final product = await context.read<AppProvider>().createProduct(
                      Product(name: capturedName, aliases: [], price: price));
                    if (capturedImage != null && product.id != null) {
                      final bytes = await capturedImage.readAsBytes();
                      await ApiService.uploadProductImage(product.id!, null,
                        bytes: bytes, filename: capturedImage.name);
                      await context.read<AppProvider>().refreshProducts();
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.red.shade700));
                  }
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── Acciones al tocar tarjeta (toggles) ──────────────────
  void _showCardActions(Product p) {
    final provider = context.read<AppProvider>();
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle bar
          Center(child: Container(
            width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          )),
          // Cabecera
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              Expanded(child: Text(p.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              Text('\$${NumberFormat('#,###', 'es_CO').format(p.price)}',
                style: TextStyle(color: scheme.primary,
                  fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
          const Divider(height: 1),
          // Toggle disponibilidad
          _toggleTile(
            icon: p.available ? Icons.visibility_off : Icons.visibility,
            iconColor: p.available ? Colors.orange : Colors.green,
            title: p.available ? 'Marcar como NO disponible' : 'Marcar como disponible',
            subtitle: p.available ? 'Actualmente disponible' : 'Actualmente no disponible',
            onTap: () async {
              Navigator.pop(context);
              await provider.updateProduct(p.id!, {'available': p.available ? 0 : 1});
            },
          ),
          // Toggle favorito
          _toggleTile(
            icon: p.favorite ? Icons.star_border : Icons.star,
            iconColor: p.favorite ? Colors.grey : Colors.amber,
            title: p.favorite ? 'Quitar de favoritos' : 'Marcar como favorito',
            subtitle: p.favorite ? 'Actualmente en favoritos' : 'Sin marcar como favorito',
            onTap: () async {
              Navigator.pop(context);
              await provider.updateProduct(p.id!, {'favorite': p.favorite ? 0 : 1});
            },
          ),
          // Toggle fiado
          _toggleTile(
            icon: p.noFiado ? Icons.attach_money : Icons.money_off,
            iconColor: p.noFiado ? Colors.green : Colors.red,
            title: p.noFiado ? 'Permitir fiado' : 'No aceptar fiado',
            subtitle: p.noFiado ? 'Actualmente: NO se fía' : 'Actualmente: sí se fía',
            onTap: () async {
              Navigator.pop(context);
              await provider.updateProduct(p.id!, {'no_fiado': p.noFiado ? 0 : 1});
            },
          ),
          const Divider(height: 1),
          // Fotos
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.photo_library_outlined, color: Colors.blue, size: 22),
            ),
            title: Text('Fotos (${p.images.length})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(p.images.isEmpty ? 'Sin fotos' : 'Ver y gestionar fotos',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            onTap: () async {
              Navigator.pop(context);
              await _showImageManager(p);
            },
          ),
          const Divider(height: 1),
          // Eliminar
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Eliminar producto',
              style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Eliminar'),
                  content: Text('¿Eliminar "${p.name}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Eliminar')),
                  ],
                ),
              );
              if (confirm == true) await provider.deleteProduct(p.id!);
            },
          ),
          const SizedBox(height: 12),
        ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showImageManager(Product p) async {
    final picker = ImagePicker();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final images = List<String>.from(p.images);
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Fotos de ${p.name}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (images.isNotEmpty)
                SizedBox(height: 110, child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: ApiService.productImageUrl(images[i]),
                        httpHeaders: ApiService.imageHeaders,
                        width: 100, height: 100, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 100, height: 100, color: Colors.grey.shade100),
                      ),
                    ),
                    Positioned(top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            await ApiService.deleteProductImage(p.id!, images[i]);
                            setModal(() => images.removeAt(i));
                            await context.read<AppProvider>().refreshProducts();
                          } catch (_) {}
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                        ),
                      )),
                  ]),
                )),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text('Agregar foto'),
                  onPressed: () async {
                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                    if (picked == null) return;
                    try {
                      final bytes = await picked.readAsBytes();
                      final filename = await ApiService.uploadProductImage(p.id!, null,
                        bytes: bytes, filename: picked.name);
                      setModal(() => images.add(filename));
                      await context.read<AppProvider>().refreshProducts();
                    } catch (_) {}
                  },
                )),
            ]),
          );
        },
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required VoidCallback onTap,
  }) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: iconColor, size: 22),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    onTap: onTap,
  );

  Widget _badge(String text, Color color) => Container(
    margin: const EdgeInsets.only(top: 4, right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(
      fontSize: 10, color: color, fontWeight: FontWeight.bold)),
  );

  @override
  Widget build(BuildContext context) {
    final provider  = context.watch<AppProvider>();
    final products  = provider.products;
    final scheme    = Theme.of(context).colorScheme;

    return Scaffold(
      body: products.isEmpty
        ? const EmptyState(
            icon: Icons.inventory_2_rounded,
            title: 'Sin productos',
            subtitle: 'Agrega uno con +',
          )
        : ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: products.length,
            itemBuilder: (ctx, i) {
              final p = products[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: provider.isAdmin ? () => _showCardActions(p) : null,
                    child: Padding(padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        // Icono estado
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: !p.available
                              ? Colors.orange.withValues(alpha: 0.12)
                              : p.favorite
                                ? Colors.amber.withValues(alpha: 0.12)
                                : scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            !p.available
                              ? Icons.visibility_off
                              : p.favorite ? Icons.star : Icons.inventory_2_outlined,
                            color: !p.available
                              ? Colors.orange
                              : p.favorite ? Colors.amber : scheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15))),
                            Text(
                              '\$${NumberFormat('#,###', 'es_CO').format(p.price)}',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold)),
                          ]),
                          if (p.aliases.isNotEmpty)
                            Text(p.aliases.join(', '),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          Row(children: [
                            if (!p.available)  _badge('NO DISPONIBLE', Colors.orange),
                            if (p.noFiado)     _badge('NO SE FÍA', Colors.red),
                            if (p.favorite)    _badge('FAVORITO', Colors.amber.shade700),
                          ]),
                        ])),
                        // Indicador visual de que es tappable
                        Icon(Icons.tune, size: 16, color: Colors.grey.shade400),
                      ])),
                  ),
                ),
              );
            }),
      floatingActionButton: provider.isAdmin
        ? FloatingActionButton.extended(
            onPressed: _showAddProduct,
            icon: const Icon(Icons.add),
            label: const Text('Producto'),
            backgroundColor: scheme.primary,
            foregroundColor: Colors.white,
          )
        : null,
    );
  }
}
