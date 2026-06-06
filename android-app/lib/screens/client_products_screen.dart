import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import 'client_product_detail.dart';

class ClientProductsScreen extends StatefulWidget {
  const ClientProductsScreen({super.key});
  @override State<ClientProductsScreen> createState() => _ClientProductsScreenState();
}

class _ClientProductsScreenState extends State<ClientProductsScreen> {
  static const _green = Color(0xFF1E6B2E);
  List<Product> _products = [];
  List<Product> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getProducts();
      if (mounted) setState(() {
        _products = list.where((p) => p.available).toList();
        _filtered = _products;
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() => _filtered = q.isEmpty
        ? _products
        : _products.where((p) => p.name.toLowerCase().contains(q)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar producto...',
            prefixIcon: const Icon(Icons.search, color: _green),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),

      Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _filtered.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('📦', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text(_searchCtrl.text.isNotEmpty ? 'Sin resultados' : 'Sin productos disponibles',
                    style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _green,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
                      childAspectRatio: 0.72),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _ProductCard(
                      product: _filtered[i],
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ClientProductDetail(product: _filtered[i])));
                      },
                    ),
                  ),
                )),
    ]);
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = product.images.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          Expanded(child: hasImage
              ? CachedNetworkImage(
                  imageUrl: ApiService.productImageUrl(product.images.first),
                  httpHeaders: ApiService.imageHeaders,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, __) => Container(
                    color: Colors.grey.shade100,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  errorWidget: (_, __, ___) => _PlaceholderImage(),
                )
              : _PlaceholderImage()),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text('\$${_fmt(product.price)}',
                style: const TextStyle(
                  color: Color(0xFF1E6B2E),
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
            ]),
          ),
        ]),
      ),
    );
  }

  String _fmt(double price) {
    if (price == price.roundToDouble()) return price.toInt().toString();
    return price.toStringAsFixed(2);
  }
}

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFE8F5E9),
    child: const Center(
      child: Icon(Icons.pets, color: Color(0xFF1E6B2E), size: 48)),
  );
}
