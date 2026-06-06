import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ClientProductDetail extends StatefulWidget {
  final Product product;
  const ClientProductDetail({super.key, required this.product});
  @override State<ClientProductDetail> createState() => _ClientProductDetailState();
}

class _ClientProductDetailState extends State<ClientProductDetail> {
  static const _green = Color(0xFF1E6B2E);
  int _qty = 1;
  DateTime? _deliveryDate;
  bool _adding = false;
  int _imgIndex = 0;

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    try {
      await ApiService.addToCart(
        widget.product.id!,
        _qty,
        deliveryDate: _deliveryDate != null
            ? DateFormat('yyyy-MM-dd').format(_deliveryDate!)
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Agregado al carrito'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _green)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deliveryDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(p.name, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [
        Expanded(child: SingleChildScrollView(children: [
          // Image carousel
          if (p.images.isNotEmpty)
            SizedBox(
              height: 260,
              child: Stack(children: [
                PageView.builder(
                  itemCount: p.images.length,
                  onPageChanged: (i) => setState(() => _imgIndex = i),
                  itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: ApiService.productImageUrl(p.images[i]),
                    httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, __) => Container(color: Colors.grey.shade100,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFE8F5E9),
                      child: const Center(child: Icon(Icons.pets, color: _green, size: 64))),
                  ),
                ),
                if (p.images.length > 1)
                  Positioned(bottom: 8, left: 0, right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(p.images.length, (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _imgIndex ? 12 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _imgIndex ? _green : Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(3)),
                      )),
                    ),
                  ),
              ]),
            )
          else
            Container(
              height: 200, color: const Color(0xFFE8F5E9),
              child: const Center(child: Icon(Icons.pets, color: _green, size: 80))),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Name + price
              Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('\$${_fmt(p.price)} / unidad',
                style: const TextStyle(fontSize: 18, color: _green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Quantity selector
              const Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Row(children: [
                _QtyButton(icon: Icons.remove, onTap: _qty > 1 ? () => setState(() => _qty--) : null),
                const SizedBox(width: 16),
                Text('$_qty', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                _QtyButton(icon: Icons.add, onTap: () => setState(() => _qty++)),
              ]),
              const SizedBox(height: 8),
              Text('Subtotal: \$${_fmt(p.price * _qty)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),

              const SizedBox(height: 20),

              // Delivery date
              const Text('Fecha de entrega (opcional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded, color: _green, size: 18),
                    const SizedBox(width: 10),
                    Text(_deliveryDate != null
                        ? DateFormat('dd/MM/yyyy').format(_deliveryDate!)
                        : 'Seleccionar fecha',
                      style: TextStyle(
                        color: _deliveryDate != null ? Colors.black87 : Colors.grey.shade400)),
                    const Spacer(),
                    if (_deliveryDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _deliveryDate = null),
                        child: Icon(Icons.close, size: 16, color: Colors.grey.shade400)),
                  ]),
                ),
              ),
            ]),
          ),
        ])),

        // Add to cart button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(width: double.infinity, height: 52,
              child: FilledButton.icon(
                onPressed: _adding ? null : _addToCart,
                icon: _adding
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.shopping_cart_rounded),
                label: Text(_adding ? 'Agregando...' : 'Agregar al carrito',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(0);
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _QtyButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: onTap != null ? const Color(0xFF1E6B2E) : Colors.grey.shade200,
        shape: BoxShape.circle),
      child: Icon(icon,
        color: onTap != null ? Colors.white : Colors.grey.shade400, size: 20),
    ),
  );
}
