import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ClientProductDetail extends StatefulWidget {
  final Product product;
  final String  description;
  const ClientProductDetail({super.key, required this.product, required this.description});
  @override State<ClientProductDetail> createState() => _ClientProductDetailState();
}

class _ClientProductDetailState extends State<ClientProductDetail> {
  static const _green = Color(0xFF1E6B2E);
  static const _gold  = Color(0xFFD4800A);

  int       _qty      = 1;
  DateTime? _delivDate;
  bool      _adding   = false;
  int       _imgIndex = 0;
  final     _pageCtrl = PageController();

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  double get _subtotal => widget.product.price * _qty;

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    try {
      await ApiService.addToCart(
        widget.product.id!,
        _qty,
        deliveryDate: _delivDate != null ? DateFormat('yyyy-MM-dd').format(_delivDate!) : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('$_qty × ${widget.product.name} agregado al carrito'),
          ]),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      helpText: 'Fecha de entrega preferida',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _green)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _delivDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p    = widget.product;
    final size = MediaQuery.of(context).size;
    final imgH = size.height * 0.38;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // Scrollable content
        CustomScrollView(slivers: [
          // Hero image area
          SliverAppBar(
            expandedHeight: imgH,
            pinned: true,
            backgroundColor: _green,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: p.images.isNotEmpty
                ? Stack(children: [
                    PageView.builder(
                      controller: _pageCtrl,
                      itemCount: p.images.length,
                      onPageChanged: (i) => setState(() => _imgIndex = i),
                      itemBuilder: (_, i) => CachedNetworkImage(
                        imageUrl: ApiService.productImageUrl(p.images[i]),
                        httpHeaders: ApiService.imageHeaders,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => Container(color: const Color(0xFFE8F5E9),
                          child: const Center(child: CircularProgressIndicator(color: _green, strokeWidth: 2))),
                        errorWidget: (_, __, ___) => _ImgFallback(),
                      ),
                    ),
                    // Dots
                    if (p.images.length > 1)
                      Positioned(bottom: 16, left: 0, right: 0,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(p.images.length, (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _imgIndex ? 14 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _imgIndex ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(4)),
                          )),
                        ),
                      ),
                  ])
                : _ImgFallback(),
            ),
          ),

          // Content
          SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title row
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(p.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2))),
                  if (p.favorite)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: const Text('⭐ Top', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ]),
                const SizedBox(height: 8),
                // Price
                Row(children: [
                  Text('\$${_fmt(p.price)}',
                    style: const TextStyle(fontSize: 26, color: _green, fontWeight: FontWeight.w800)),
                  const Text(' / unidad',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                ]),
                const SizedBox(height: 16),

                // Description
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFB2DFDB)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.info_outline_rounded, color: _green, size: 16),
                      SizedBox(width: 6),
                      Text('Descripción', style: TextStyle(color: _green, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                    const SizedBox(height: 8),
                    Text(widget.description,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.5)),
                  ]),
                ),
                const SizedBox(height: 16),

                // Payment info — Contraentrega badge
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.local_shipping_rounded, color: Colors.orange.shade700, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pago Contraentrega', style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.orange.shade800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('Paga en efectivo al recibir tu pedido. Sin adelantos requeridos.',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),

                // Quantity
                const Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                Row(children: [
                  _QtyBtn(icon: Icons.remove_rounded,
                    onTap: _qty > 1 ? () => setState(() => _qty--) : null),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text('$_qty', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  _QtyBtn(icon: Icons.add_rounded, onTap: () => setState(() => _qty++)),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Subtotal', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('\$${_fmt(_subtotal)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _green)),
                  ]),
                ]),
                const SizedBox(height: 20),

                // Delivery date (optional)
                const Text('Fecha de entrega (opcional)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded, color: _green, size: 20),
                      const SizedBox(width: 12),
                      Text(_delivDate != null
                        ? '📅 ${DateFormat('EEEE dd/MM/yyyy', 'es').format(_delivDate!)}'
                        : 'Seleccionar fecha preferida',
                        style: TextStyle(
                          color: _delivDate != null ? Colors.black87 : Colors.grey.shade500,
                          fontWeight: _delivDate != null ? FontWeight.w600 : FontWeight.normal)),
                      const Spacer(),
                      if (_delivDate != null)
                        GestureDetector(
                          onTap: () => setState(() => _delivDate = null),
                          child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400)),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),

                // Details chips
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _InfoChip(icon: Icons.verified_rounded, label: 'Calidad garantizada', color: _green),
                  if (!p.noFiado) _InfoChip(icon: Icons.handshake_rounded, label: 'Disponible a fiado', color: const Color(0xFF1565C0)),
                  _InfoChip(icon: Icons.delivery_dining_rounded, label: 'Entrega a domicilio', color: Colors.purple),
                ]),

                const SizedBox(height: 100), // space for bottom button
              ]),
            ),
          ])),
        ]),

        // Add to cart button (floating)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 16, offset: const Offset(0, -4))],
            ),
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
            child: Row(children: [
              // Total
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('\$${_fmt(_subtotal)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _green)),
              ]),
              const SizedBox(width: 16),
              Expanded(child: SizedBox(height: 52,
                child: FilledButton.icon(
                  onPressed: _adding ? null : _addToCart,
                  icon: _adding
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_shopping_cart_rounded, size: 20),
                  label: Text(_adding ? 'Agregando...' : 'Agregar al carrito',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              )),
            ]),
          ),
        ),
      ]),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(0);
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _QtyBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: onTap != null ? const Color(0xFF1E6B2E) : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Icon(icon,
        color: onTap != null ? Colors.white : Colors.grey.shade400, size: 22),
    ),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _ImgFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFE8F5E9),
    child: const Center(child: Icon(Icons.pets_rounded, color: Color(0xFF1E6B2E), size: 80)),
  );
}
