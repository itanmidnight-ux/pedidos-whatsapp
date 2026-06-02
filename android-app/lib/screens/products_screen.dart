import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../models/product.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {

  // ── Agregar producto ──────────────────────────────────────
  void _showAddProduct() {
    final nameCtrl  = TextEditingController();
    final priceCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    final aliases   = <String>[];

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nuevo Producto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del producto', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Precio', border: OutlineInputBorder(), prefixText: '\$'),
              keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Agregar apodo/alias', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                onPressed: () {
                  if (aliasCtrl.text.trim().isNotEmpty) {
                    setModal(() { aliases.add(aliasCtrl.text.trim()); aliasCtrl.clear(); });
                  }
                }),
            ]),
            if (aliases.isNotEmpty) Wrap(spacing: 6, children: aliases
              .map((a) => Chip(label: Text(a),
                onDeleted: () => setModal(() => aliases.remove(a)))).toList()),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () async {
                final price = double.tryParse(
                  priceCtrl.text.replaceAll(',', '').replaceAll('.', ''));
                if (nameCtrl.text.trim().isEmpty || price == null) return;
                Navigator.pop(ctx);
                await context.read<AppProvider>().createProduct(
                  Product(name: nameCtrl.text.trim(),
                    aliases: List.from(aliases), price: price));
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2D5016)),
              child: const Text('Guardar Producto'),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Acciones al tocar tarjeta (toggles) ──────────────────
  void _showCardActions(Product p) {
    final provider = context.read<AppProvider>();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Cabecera
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(child: Text(p.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              Text('\$${NumberFormat('#,###', 'es_CO').format(p.price)}',
                style: const TextStyle(color: Color(0xFF2D5016),
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
          const SizedBox(height: 8),
        ]),
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
        color: iconColor.withOpacity(0.12),
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
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(
      fontSize: 10, color: color, fontWeight: FontWeight.bold)),
  );

  @override
  Widget build(BuildContext context) {
    final provider  = context.watch<AppProvider>();
    final products  = provider.products;

    return Scaffold(
      body: products.isEmpty
        ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Sin productos. Agrega uno con +',
              style: TextStyle(color: Colors.grey)),
          ]))
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
                    onTap: () => _showCardActions(p),
                    child: Padding(padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        // Icono estado
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: !p.available
                              ? Colors.orange.withOpacity(0.12)
                              : p.favorite
                                ? Colors.amber.withOpacity(0.12)
                                : const Color(0xFF2D5016).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            !p.available
                              ? Icons.visibility_off
                              : p.favorite ? Icons.star : Icons.inventory_2_outlined,
                            color: !p.available
                              ? Colors.orange
                              : p.favorite ? Colors.amber : const Color(0xFF2D5016),
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
                              style: const TextStyle(
                                color: Color(0xFF2D5016),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProduct,
        icon: const Icon(Icons.add),
        label: const Text('Producto'),
        backgroundColor: const Color(0xFF2D5016),
        foregroundColor: Colors.white,
      ),
    );
  }
}
