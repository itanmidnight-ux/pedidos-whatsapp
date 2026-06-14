import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ClientProductDetailState extends State<ClientProductDetail>
    with SingleTickerProviderStateMixin {
  static const _green     = Color(0xFF1A7A35);
  static const _greenDark = Color(0xFF0F4D20);
  static const _gold      = Color(0xFFD4800A);

  int       _qty      = 1;
  DateTime? _delivDate;
  bool      _adding   = false;
  int       _imgIndex = 0;
  final     _pageCtrl = PageController();

  late final AnimationController _addCtrl;
  late final Animation<double>   _addScale;

  @override
  void initState() {
    super.initState();
    _addCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _addScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _addCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _addCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => widget.product.price * _qty;

  Future<void> _addToCart() async {
    HapticFeedback.mediumImpact();
    await _addCtrl.forward();
    await _addCtrl.reverse();
    setState(() => _adding = true);
    try {
      await ApiService.addToCart(
        widget.product.id!,
        _qty,
        deliveryDate: _delivDate != null ? DateFormat('yyyy-MM-dd').format(_delivDate!) : null,
      );
      if (mounted) {
        _showSuccessSheet();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showSuccessSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24,
          MediaQuery.of(context).padding.bottom + 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: _green, size: 44),
          ),
          const SizedBox(height: 16),
          const Text('¡Agregado al carrito!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${widget.product.name} × $_qty',
            style: const TextStyle(color: Colors.black54, fontSize: 14)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: const BorderSide(color: _green),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Seguir comprando', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                // will show cart tab
              },
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Ver carrito', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ]),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      helpText: 'Fecha de entrega preferida',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _green, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _delivDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p    = widget.product;
    final size = MediaQuery.of(context).size;
    final imgH = (size.height * 0.42).clamp(260.0, 380.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      body: Stack(children: [
        CustomScrollView(slivers: [
          // ── Hero image ───────────────────────────────────────
          SliverAppBar(
            expandedHeight: imgH,
            pinned: true,
            backgroundColor: _greenDark,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: p.images.isNotEmpty
                ? Stack(children: [
                    // Image gallery with zoom
                    PageView.builder(
                      controller: _pageCtrl,
                      itemCount: p.images.length,
                      onPageChanged: (i) => setState(() => _imgIndex = i),
                      itemBuilder: (_, i) => InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 3.0,
                        child: CachedNetworkImage(
                          imageUrl: ApiService.productImageUrl(p.images[i]),
                          httpHeaders: ApiService.imageHeaders,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFFE8F5E9),
                            child: const Center(child: CircularProgressIndicator(
                              color: _green, strokeWidth: 2))),
                          errorWidget: (_, __, ___) => _ImgFallback(),
                        ),
                      ),
                    ),
                    // Dark gradient bottom
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    // Photo dots
                    if (p.images.length > 1)
                      Positioned(bottom: 14, left: 0, right: 0,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(p.images.length, (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _imgIndex ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _imgIndex ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(4)),
                          )),
                        ),
                      ),
                    // Favorite badge
                    if (p.favorite)
                      Positioned(top: 0, right: 0,
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.star_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Más vendido',
                              style: TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ),
                  ])
                : _ImgFallback(),
            ),
          ),

          // ── Content ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Name & price card
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name,
                    style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, height: 1.2,
                      color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Precio por unidad',
                        style: TextStyle(color: Colors.black38, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text('\$${_fmt(p.price)}',
                        style: const TextStyle(
                          fontSize: 32, color: _green,
                          fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ]),
                    const Spacer(),
                    // Stock chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _green.withValues(alpha: 0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.inventory_2_outlined, size: 14, color: _green),
                        SizedBox(width: 5),
                        Text('Disponible',
                          style: TextStyle(color: _green, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ]),
              ),

              const SizedBox(height: 8),

              // Description
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _SectionTitle(icon: Icons.info_outline_rounded, label: 'Descripción'),
                  const SizedBox(height: 10),
                  Text(widget.description,
                    style: const TextStyle(
                      color: Color(0xFF4A4A4A), fontSize: 14, height: 1.6)),
                ]),
              ),

              const SizedBox(height: 8),

              // Benefits row
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(children: [
                  _BenefitTile(
                    icon: Icons.local_shipping_rounded,
                    label: 'Entrega\na domicilio',
                    color: Colors.blue.shade600),
                  _BenefitTile(
                    icon: Icons.payments_outlined,
                    label: 'Pago\ncontraentrega',
                    color: Colors.orange.shade700),
                  _BenefitTile(
                    icon: Icons.verified_rounded,
                    label: 'Calidad\ngarantizada',
                    color: _green),
                  if (!p.noFiado)
                    _BenefitTile(
                      icon: Icons.handshake_rounded,
                      label: 'Disponible\na fiado',
                      color: Colors.purple.shade600),
                ]),
              ),

              const SizedBox(height: 8),

              // Quantity selector
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _SectionTitle(icon: Icons.shopping_cart_outlined, label: 'Cantidad'),
                  const SizedBox(height: 14),
                  Row(children: [
                    // Qty control
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _QtyBtn(
                          icon: Icons.remove_rounded,
                          enabled: _qty > 1,
                          onTap: () { if (_qty > 1) setState(() => _qty--); },
                        ),
                        SizedBox(
                          width: 56,
                          child: Text('$_qty',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A))),
                        ),
                        _QtyBtn(
                          icon: Icons.add_rounded,
                          enabled: true,
                          onTap: () => setState(() => _qty++),
                        ),
                      ]),
                    ),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Subtotal',
                        style: TextStyle(color: Colors.black38, fontSize: 11)),
                      Text('\$${_fmt(_subtotal)}',
                        style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: _green)),
                    ]),
                  ]),
                ]),
              ),

              const SizedBox(height: 8),

              // Delivery date
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _SectionTitle(
                    icon: Icons.calendar_month_rounded,
                    label: 'Fecha de entrega',
                    optional: true),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _delivDate != null
                          ? _green.withValues(alpha: 0.06)
                          : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _delivDate != null
                            ? _green.withValues(alpha: 0.4)
                            : const Color(0xFFE0E0E0)),
                      ),
                      child: Row(children: [
                        Icon(
                          _delivDate != null
                            ? Icons.event_available_rounded
                            : Icons.calendar_today_outlined,
                          color: _delivDate != null ? _green : Colors.grey.shade400,
                          size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(
                          _delivDate != null
                            ? DateFormat("EEEE d 'de' MMMM, yyyy", 'es').format(_delivDate!)
                            : 'Seleccionar fecha preferida',
                          style: TextStyle(
                            color: _delivDate != null ? _greenDark : Colors.grey.shade400,
                            fontWeight: _delivDate != null ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 14),
                        )),
                        if (_delivDate != null)
                          GestureDetector(
                            onTap: () => setState(() => _delivDate = null),
                            child: Icon(Icons.close_rounded,
                              size: 18, color: Colors.grey.shade400)),
                        if (_delivDate == null)
                          Icon(Icons.chevron_right_rounded,
                            size: 20, color: Colors.grey.shade300),
                      ]),
                    ),
                  ),
                  if (_delivDate == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text('Si no seleccionas fecha, coordinaremos contigo',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                    ),
                ]),
              ),

              const SizedBox(height: 100),
            ]),
          ),
        ]),

        // ── Sticky bottom CTA ─────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20, offset: const Offset(0, -6))],
            ),
            padding: EdgeInsets.fromLTRB(
              20, 14, 20, MediaQuery.of(context).padding.bottom + 14),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total del pedido',
                  style: TextStyle(color: Colors.black38, fontSize: 11)),
                Text('\$${_fmt(_subtotal)}',
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: _green)),
              ]),
              const SizedBox(width: 16),
              Expanded(
                child: ScaleTransition(
                  scale: _addScale,
                  child: SizedBox(height: 54,
                    child: ElevatedButton(
                      onPressed: _adding ? null : _addToCart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        disabledBackgroundColor: _green.withValues(alpha: 0.45),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: _green.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _adding
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_shopping_cart_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Agregar al carrito',
                                style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  static String _fmt(double v) => NumberFormat('#,##0', 'es').format(v.round());
}

// ── Reusable widgets ───────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     optional;
  const _SectionTitle({required this.icon, required this.label, this.optional = false});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: const Color(0xFF1A7A35)),
    const SizedBox(width: 6),
    Text(label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
    if (optional) ...[
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('Opcional',
          style: TextStyle(fontSize: 10, color: Colors.grey)),
      ),
    ],
  ]);
}

class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _BenefitTile({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    ),
    const SizedBox(height: 6),
    Text(label,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3)),
  ]));
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool     enabled;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF1A7A35) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon,
        size: 22,
        color: enabled ? Colors.white : Colors.grey.shade300),
    ),
  );
}

class _ImgFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFE8F5E9),
    child: const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.pets_rounded, color: Color(0xFF1A7A35), size: 80),
        SizedBox(height: 12),
        Text('Imagen no disponible',
          style: TextStyle(color: Color(0xFF1A7A35), fontSize: 13)),
      ]),
    ),
  );
}
